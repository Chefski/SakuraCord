import Foundation

/// Edits HEIF/AVIF metadata item payloads in place so image extents and codec data
/// never move. Supports file and idat extents; unfamiliar layouts fail closed.
enum HEIFMetadataRemover {
    private struct Box {
        let type: String
        let typeOffset: Int
        let payload: Range<Int>
    }

    static func remove(_ data: Data, orientation: Int) throws -> Data {
        let top = try boxes(data, in: 0 ..< data.count)
        guard top.filter({ $0.type == "meta" }).count == 1,
              let meta = top.first(where: { $0.type == "meta" }), meta.payload.count >= 4 else {
            throw UploadMetadataError.unsupportedMedia
        }
        let children = try boxes(data, in: meta.payload.lowerBound + 4 ..< meta.payload.upperBound)
        var result = data
        try clearContainerMetadata(top, retaining: ["ftyp", "meta", "mdat"], in: &result)
        try clearContainerMetadata(children, retaining: ["hdlr", "pitm", "iloc", "iinf", "iprp", "iref", "idat", "dinf", "grpl"], in: &result)
        guard let info = children.first(where: { $0.type == "iinf" }),
              let locations = children.first(where: { $0.type == "iloc" })
        else { throw UploadMetadataError.unsupportedMedia }
        let items = try metadataItems(data, info: info)
        if items.isEmpty { return result }
        let extents = try itemExtents(data, box: locations, idat: children.first(where: { $0.type == "idat" })?.payload, wanted: Set(items.keys))
        for (id, type) in items {
            guard let ranges = extents[id], !ranges.isEmpty else { throw UploadMetadataError.unsupportedMedia }
            let size = ranges.reduce(0) { $0 + $1.count }
            guard size <= data.count else { throw UploadMetadataError.unsupportedMedia }
            let replacement = type == "Exif"
                ? Data(repeating: 0, count: 4) + ImageMetadataContainers.orientationTIFF(orientation)
                : Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"/>".utf8)
            guard replacement.count <= size else { throw UploadMetadataError.unsupportedMedia }
            var clean = replacement
            clean.append(Data(repeating: type == "Exif" ? 0 : 32, count: size - clean.count))
            var position = 0
            for range in ranges {
                result.replaceSubrange(range, with: clean[position ..< position + range.count])
                position += range.count
            }
        }
        return result
    }

    private static func clearContainerMetadata(_ boxes: [Box], retaining types: Set<String>, in data: inout Data) throws {
        // XMP may live outside iinf/iloc. Replace its box with equally sized,
        // empty padding so every absolute image extent remains valid.
        let xmpUUID: [UInt8] = [0xBE, 0x7A, 0xCF, 0xCB, 0x97, 0xA9, 0x42, 0xE8, 0x9C, 0x71, 0x99, 0x94, 0x91, 0xE3, 0xAF, 0xAC]
        for box in boxes where !types.contains(box.type) {
            try Task.checkCancellation()
            switch box.type {
            case "uuid":
                guard data[box.payload].prefix(16).elementsEqual(xmpUUID) else { throw UploadMetadataError.unsupportedMedia }
            case "xml ", "free", "skip": break
            default: throw UploadMetadataError.unsupportedMedia
            }
            data.replaceSubrange(box.typeOffset ..< box.typeOffset + 4, with: Data("free".utf8))
            data.resetBytes(in: box.payload)
        }
    }

    private static func metadataItems(_ data: Data, info: Box) throws -> [Int: String] {
        var cursor = info.payload.lowerBound
        let version = try integer(data, at: &cursor, bytes: 1, end: info.payload.upperBound)
        cursor += 3
        _ = try integer(data, at: &cursor, bytes: version == 0 ? 2 : 4, end: info.payload.upperBound)
        var items: [Int: String] = [:]
        for entry in try boxes(data, in: cursor ..< info.payload.upperBound) where entry.type == "infe" {
            var offset = entry.payload.lowerBound
            let version = try integer(data, at: &offset, bytes: 1, end: entry.payload.upperBound)
            guard version == 2 || version == 3 else { throw UploadMetadataError.unsupportedMedia }
            offset += 3
            let id = try integer(data, at: &offset, bytes: version == 2 ? 2 : 4, end: entry.payload.upperBound)
            _ = try integer(data, at: &offset, bytes: 2, end: entry.payload.upperBound)
            guard entry.payload.upperBound - offset >= 4 else { throw UploadMetadataError.unsupportedMedia }
            let type = String(bytes: data[offset ..< offset + 4], encoding: .ascii) ?? ""
            if type == "Exif" || type == "mime" { items[id] = type }
            if type == "uri " { throw UploadMetadataError.unsupportedMedia }
        }
        return items
    }

    private static func itemExtents(_ data: Data, box: Box, idat: Range<Int>?, wanted: Set<Int>) throws -> [Int: [Range<Int>]] {
        var cursor = box.payload.lowerBound
        let end = box.payload.upperBound
        let version = try integer(data, at: &cursor, bytes: 1, end: end)
        guard version <= 2 else { throw UploadMetadataError.unsupportedMedia }
        cursor += 3
        let sizes = try integer(data, at: &cursor, bytes: 1, end: end)
        let baseSizes = try integer(data, at: &cursor, bytes: 1, end: end)
        let count = try integer(data, at: &cursor, bytes: version < 2 ? 2 : 4, end: end)
        var result: [Int: [Range<Int>]] = [:]
        for _ in 0 ..< count {
            try Task.checkCancellation()
            let id = try integer(data, at: &cursor, bytes: version < 2 ? 2 : 4, end: end)
            let method = version == 0 ? 0 : try integer(data, at: &cursor, bytes: 2, end: end) & 15
            let reference = try integer(data, at: &cursor, bytes: 2, end: end)
            let base = try integer(data, at: &cursor, bytes: baseSizes >> 4, end: end)
            let extentCount = try integer(data, at: &cursor, bytes: 2, end: end)
            var ranges: [Range<Int>] = []
            for _ in 0 ..< extentCount {
                if version != 0 { _ = try integer(data, at: &cursor, bytes: baseSizes & 15, end: end) }
                let offset = try integer(data, at: &cursor, bytes: sizes >> 4, end: end)
                let length = try integer(data, at: &cursor, bytes: sizes & 15, end: end)
                guard wanted.contains(id) else { continue }
                guard reference == 0, method <= 1, method == 0 || idat != nil else { throw UploadMetadataError.unsupportedMedia }
                let origin = method == 1 ? idat!.lowerBound : 0
                let limit = method == 1 ? idat!.upperBound : data.count
                guard base <= limit - origin, offset <= limit - origin - base else { throw UploadMetadataError.unsupportedMedia }
                let start = origin + base + offset
                guard length > 0, length <= limit - start else { throw UploadMetadataError.unsupportedMedia }
                ranges.append(start ..< start + length)
            }
            if wanted.contains(id) { result[id] = ranges }
        }
        return result
    }

    private static func boxes(_ data: Data, in range: Range<Int>) throws -> [Box] {
        guard range.lowerBound >= 0, range.upperBound <= data.count else { throw UploadMetadataError.unsupportedMedia }
        var cursor = range.lowerBound
        var result: [Box] = []
        while cursor < range.upperBound {
            let start = cursor
            var size = try integer(data, at: &cursor, bytes: 4, end: range.upperBound)
            guard range.upperBound - cursor >= 4 else { throw UploadMetadataError.unsupportedMedia }
            let type = String(bytes: data[cursor ..< cursor + 4], encoding: .ascii) ?? ""
            cursor += 4
            if size == 1 { size = try integer(data, at: &cursor, bytes: 8, end: range.upperBound) }
            if size == 0 { size = range.upperBound - start }
            guard size >= cursor - start, size <= range.upperBound - start else { throw UploadMetadataError.unsupportedMedia }
            result.append(Box(type: type, typeOffset: start + 4, payload: cursor ..< start + size))
            cursor = start + size
        }
        return result
    }

    private static func integer(_ data: Data, at cursor: inout Int, bytes: Int, end: Int) throws -> Int {
        guard bytes <= 8, cursor <= end, bytes <= end - cursor else { throw UploadMetadataError.unsupportedMedia }
        var value: UInt64 = 0
        for byte in data[cursor ..< cursor + bytes] { value = (value << 8) | UInt64(byte) }
        cursor += bytes
        guard let result = Int(exactly: value) else { throw UploadMetadataError.unsupportedMedia }
        return result
    }
}
