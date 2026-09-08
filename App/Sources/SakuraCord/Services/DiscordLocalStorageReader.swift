import Foundation

/// A bounded, read-only reader for Chromium's LevelDB local storage. Only files
/// referenced by CURRENT/MANIFEST are considered; obsolete values and tombstones
/// must never become importable sessions.
nonisolated enum DiscordLocalStorageReader {
    static let maximumBytes = 128 * 1024 * 1024

    static func read(directory: URL, keys: Set<Data>) throws -> [Data: Data] {
        let currentURL = directory.appending(path: "CURRENT")
        let current = try boundedRead(currentURL)
        guard let name = String(data: current, encoding: .utf8)?.trimmingCharacters(in: .newlines),
              name.hasPrefix("MANIFEST-"), name.dropFirst(9).allSatisfy(\.isNumber),
              name.count > 9 else { throw StorageError.invalid }
        let manifestURL = directory.appending(path: name)
        let manifestData = try boundedRead(manifestURL)
        let manifest = try Manifest(data: manifestData)
        var records: [Data: Record] = [:]
        var total = manifestData.count
        for number in manifest.tables.sorted() {
            try Task.checkCancellation()
            let data = try boundedRead(directory.appending(path: String(format: "%06llu.ldb", number)))
            total += data.count
            guard total <= maximumBytes else { throw StorageError.invalid }
            try readTable(data) { key, value in
                guard key.count >= 8 else { throw StorageError.invalid }
                var trailer = Cursor(Data(key.suffix(8)))
                let tag = try trailer.fixed(8)
                try merge(Data(key.dropLast(8)), value: value, sequence: tag >> 8,
                          kind: tag & 255, keys: keys, records: &records)
            }
        }
        let logs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { url in
                guard url.pathExtension == "log", let number = UInt64(url.deletingPathExtension().lastPathComponent)
                else { return false }
                return number >= manifest.logNumber || number == manifest.previousLog
            }
        var logSnapshots: [(URL, Data)] = []
        for url in logs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data = try boundedRead(url)
            total += data.count
            guard total <= maximumBytes else { throw StorageError.invalid }
            logSnapshots.append((url, data))
            for batch in try logRecords(data) {
                var cursor = Cursor(batch)
                let sequence = try cursor.fixed(8)
                let count = try cursor.fixed(4)
                guard count <= UInt64(batch.count), sequence <= (UInt64.max >> 8) - count
                else { throw StorageError.invalid }
                for index in 0 ..< count {
                    let kind = try cursor.fixed(1)
                    let key = try cursor.bytes()
                    let value = kind == 1 ? try cursor.bytes() : Data()
                    try merge(key, value: value, sequence: sequence + index, kind: kind, keys: keys, records: &records)
                }
                guard cursor.isAtEnd else { throw StorageError.invalid }
            }
        }
        // A concurrent compaction or write invalidates the snapshot. Never mix
        // generations or silently fall back to scanning abandoned files.
        guard try boundedRead(currentURL) == current,
              try boundedRead(manifestURL) == manifestData else { throw StorageError.changed }
        for (url, data) in logSnapshots where try boundedRead(url) != data {
            throw StorageError.changed
        }
        return records.compactMapValues { $0.value }
    }

    private struct Record {
        var sequence: UInt64
        var value: Data?
    }

    private static func merge(
        _ key: Data, value: Data, sequence: UInt64, kind: UInt64,
        keys: Set<Data>, records: inout [Data: Record]
    ) throws {
        guard kind <= 1 else { throw StorageError.invalid }
        guard keys.contains(key), records[key].map({ $0.sequence < sequence }) ?? true else { return }
        records[key] = Record(sequence: sequence, value: kind == 1 ? value : nil)
    }

    private static func boundedRead(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes
        else { throw StorageError.invalid }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw StorageError.invalid }
        return data
    }

    private struct Manifest {
        var tables: Set<UInt64> = []
        var logNumber: UInt64 = 0
        var previousLog: UInt64 = 0

        init(data: Data) throws {
            for record in try logRecords(data) {
                var cursor = Cursor(record)
                while !cursor.isAtEnd {
                    switch try cursor.varint() {
                    case 1:
                        guard try cursor.bytes() == Data("leveldb.BytewiseComparator".utf8)
                        else { throw StorageError.invalid }
                    case 2: logNumber = try cursor.varint()
                    case 3, 4: _ = try cursor.varint()
                    case 5:
                        _ = try cursor.varint()
                        _ = try cursor.bytes()
                    case 6:
                        _ = try cursor.varint()
                        tables.remove(try cursor.varint())
                    case 7:
                        _ = try cursor.varint()
                        tables.insert(try cursor.varint())
                        _ = try cursor.varint()
                        _ = try cursor.bytes()
                        _ = try cursor.bytes()
                    case 9: previousLog = try cursor.varint()
                    default: throw StorageError.invalid
                    }
                }
            }
            guard logNumber > 0 else { throw StorageError.invalid }
        }
    }

    static func logRecords(_ data: Data) throws -> [Data] {
        let input = [UInt8](data)
        var offset = 0
        var fragment: Data?
        var result: [Data] = []
        while offset < input.count {
            let remaining = 32768 - offset % 32768
            if remaining < 7 { offset += remaining; continue }
            guard input.count - offset >= 7 else { throw StorageError.changed }
            var header = Cursor(Data(input[offset ..< offset + 7]))
            let checksum = try header.fixed(4)
            let length = Int(try header.fixed(2))
            let kind = try header.fixed(1)
            if kind == 0, length == 0 {
                guard input[offset ..< min(offset + remaining, input.count)].allSatisfy({ $0 == 0 })
                else { throw StorageError.invalid }
                offset += remaining
                continue
            }
            guard length <= remaining - 7, length <= input.count - offset - 7
            else { throw StorageError.changed }
            let bytes = Data(input[offset + 7 ..< offset + 7 + length])
            guard maskedChecksum(Data([UInt8(kind)]) + bytes) == UInt32(checksum)
            else { throw StorageError.invalid }
            try assembleLogRecord(kind: kind, bytes: bytes, fragment: &fragment, result: &result)
            offset += 7 + length
        }
        guard fragment == nil else { throw StorageError.changed }
        return result
    }

    private static func assembleLogRecord(
        kind: UInt64, bytes: Data, fragment: inout Data?, result: inout [Data]
    ) throws {
        switch kind {
        case 1:
            guard fragment == nil else { throw StorageError.invalid }
            result.append(bytes)
        case 2:
            guard fragment == nil else { throw StorageError.invalid }
            fragment = bytes
        case 3, 4:
            guard var partial = fragment else { throw StorageError.invalid }
            partial.append(bytes)
            if kind == 4 {
                result.append(partial)
                fragment = nil
            } else {
                fragment = partial
            }
        default: throw StorageError.invalid
        }
    }

    private static func readTable(_ data: Data, receive: (Data, Data) throws -> Void) throws {
        guard data.count >= 48 else { throw StorageError.invalid }
        var footer = Cursor(Data(data.suffix(48)))
        _ = try footer.varint()
        _ = try footer.varint()
        let indexOffset = try footer.varint()
        let indexSize = try footer.varint()
        var magic = Cursor(Data(data.suffix(8)))
        guard try magic.fixed(8) == 0xdb47_7524_8b80_fb57 else { throw StorageError.invalid }
        let index = try tableBlock(data, offset: indexOffset, size: indexSize)
        try blockEntries(index) { _, handle in
            var cursor = Cursor(handle)
            let offset = try cursor.varint()
            let size = try cursor.varint()
            try blockEntries(tableBlock(data, offset: offset, size: size), receive: receive)
        }
    }

    private static func tableBlock(_ data: Data, offset: UInt64, size: UInt64) throws -> Data {
        guard data.count >= 5, offset <= UInt64(data.count - 5), size <= UInt64(data.count - 5) - offset
        else { throw StorageError.invalid }
        let start = Int(offset), end = start + Int(size)
        let payload = data.subdata(in: start ..< end)
        let kind = data[end]
        var checksum = Cursor(data.subdata(in: end + 1 ..< end + 5))
        guard maskedChecksum(payload + Data([kind])) == UInt32(try checksum.fixed(4))
        else { throw StorageError.invalid }
        switch kind {
        case 0: return payload
        case 1: return try uncompressSnappy(payload)
        default: throw StorageError.invalid
        }
    }

    private static func blockEntries(_ data: Data, receive: (Data, Data) throws -> Void) throws {
        guard data.count >= 4 else { throw StorageError.invalid }
        var countCursor = Cursor(Data(data.suffix(4)))
        let count = try countCursor.fixed(4)
        guard count > 0, count <= UInt64((data.count - 4) / 4) else { throw StorageError.invalid }
        var cursor = Cursor(Data(data.prefix(data.count - 4 - Int(count) * 4)))
        var previous = Data()
        while !cursor.isAtEnd {
            let shared = try cursor.varint()
            let unshared = try cursor.varint()
            let valueLength = try cursor.varint()
            guard shared <= previous.count else { throw StorageError.invalid }
            let key = Data(previous.prefix(Int(shared))) + (try cursor.take(unshared))
            let value = try cursor.take(valueLength)
            try receive(key, value)
            previous = key
        }
    }

    static func uncompressSnappy(_ data: Data) throws -> Data {
        var cursor = Cursor(data)
        let expected = try cursor.varint()
        guard expected <= maximumBytes else { throw StorageError.invalid }
        var output: [UInt8] = []
        output.reserveCapacity(Int(expected))
        while !cursor.isAtEnd {
            let tag = try cursor.fixed(1)
            if tag & 3 == 0 {
                let encoded = tag >> 2
                let length = encoded < 60 ? encoded + 1 : try cursor.fixed(Int(encoded - 59)) + 1
                guard length <= expected - UInt64(output.count) else { throw StorageError.invalid }
                output.append(contentsOf: try cursor.take(length))
            } else {
                let length: UInt64
                let offset: UInt64
                switch tag & 3 {
                case 1:
                    length = 4 + ((tag >> 2) & 7)
                    offset = ((tag & 224) << 3) | (try cursor.fixed(1))
                case 2:
                    length = 1 + (tag >> 2)
                    offset = try cursor.fixed(2)
                default:
                    length = 1 + (tag >> 2)
                    offset = try cursor.fixed(4)
                }
                guard offset > 0, offset <= output.count, length <= expected - UInt64(output.count)
                else { throw StorageError.invalid }
                var remaining = Int(length)
                let distance = Int(offset)
                while remaining > 0 {
                    output.append(output[output.count - distance])
                    remaining -= 1
                }
            }
        }
        guard output.count == expected else { throw StorageError.invalid }
        return Data(output)
    }

    static func maskedChecksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 255)] }
        crc = ~crc
        return ((crc >> 15) | (crc << 17)) &+ 0xa282_ead8
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { value in
        var crc = UInt32(value)
        for _ in 0 ..< 8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0x82f6_3b78 : 0) }
        return crc
    }

    private struct Cursor {
        let data: [UInt8]
        var offset = 0
        var isAtEnd: Bool { offset == data.count }

        init(_ data: Data) { self.data = [UInt8](data) }

        mutating func fixed(_ count: Int) throws -> UInt64 {
            guard (0 ... 8).contains(count), count <= data.count - offset else { throw StorageError.invalid }
            var value: UInt64 = 0
            for index in 0 ..< count { value |= UInt64(data[offset + index]) << (index * 8) }
            offset += count
            return value
        }

        mutating func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                let byte = try fixed(1)
                guard shift < 63 || byte <= 1 else { throw StorageError.invalid }
                result |= (byte & 127) << shift
                if byte < 128 { return result }
            }
            throw StorageError.invalid
        }

        mutating func bytes() throws -> Data { try take(varint()) }

        mutating func take(_ count: UInt64) throws -> Data {
            guard count <= data.count - offset else { throw StorageError.invalid }
            defer { offset += Int(count) }
            return Data(data[offset ..< offset + Int(count)])
        }
    }

    enum StorageError: LocalizedError {
        case invalid
        case changed

        var errorDescription: String? {
            switch self {
            case .invalid: "Discord's local account storage could not be read. Open Discord, then try again."
            case .changed: "Discord's local storage changed during import. Quit Discord, then try again."
            }
        }
    }
}
