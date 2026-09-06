import Foundation
import SakuraCordModels

extension ProfileEditingRequest {
    static func widgets(_ widgets: [ProfileWidget], originals: [ProfileWidgetDTO], userID: UserID) throws -> Self {
        let originalsByID = Dictionary(originals.compactMap { widget in widget.id.map { ($0, widget) } }, uniquingKeysWith: { first, _ in first })
        var ids = Set<String>()
        let payload = try widgets.filter { !$0.isDiscardable }.map { widget -> JSONValue in
            if let id = widget.serverID {
                guard UInt64(id) != nil, ids.insert(id).inserted, originalsByID[id] != nil else {
                    throw ChatProviderError.invalidRequest("Reload your widgets before saving this change.")
                }
            }
            let original = widget.serverID.flatMap { originalsByID[$0] }
            var body: [String: JSONValue] = [:]
            if let id = widget.serverID { body["id"] = .string(id) }
            body["data"] = try widget.content.profileWidgetJSON(original: original?.data.raw)
            return .object(body)
        }
        return Self(path: "/users/@me/widgets", method: "PUT", body: ["widgets": .array(payload)], headers: [:])
    }
}

private extension ProfileWidget.Content {
    func profileWidgetJSON(original: [String: JSONValue]?) throws -> JSONValue {
        switch self {
        case let .application(id):
            guard UInt64(id) != nil else { throw ChatProviderError.invalidRequest("Choose an available application widget.") }
            return .object(["type": .string("application"), "application_id": .string(id)])
        case let .games(kind, games):
            guard games.count <= kind.capacity, Set(games.map(\.id)).count == games.count,
                  games.allSatisfy({ UInt64($0.id) != nil && ($0.comment?.utf16.count ?? 0) <= 200 })
            else { throw ChatProviderError.invalidRequest("Check this widget's games and comments before saving.") }
            return .object(["type": .string(kind.rawValue), "games": .array(games.map { game in
                var value: [String: JSONValue] = ["game_id": .string(game.id)]
                if game.includesComment { value["comment"] = game.comment.map(JSONValue.string) ?? .null }
                if let tags = game.tags { value["tags"] = .array(tags.map(JSONValue.string)) } else if game.includesTags { value["tags"] = .null }
                return .object(value)
            })])
        case let .personal(personal):
            guard !personal.header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  personal.header.utf16.count <= 50
            else { throw ChatProviderError.invalidRequest("Give your widget a header of 50 characters or fewer.") }
            return try .object(["type": .string("personal"), "header": .string(personal.header),
                                "sections": .array(personal.sections.compactMap { try $0.profileWidgetJSON() })])
        case .unrecognized:
            guard let original else { throw ChatProviderError.invalidRequest("This widget cannot be created by this version of SakuraCord.") }
            return .object(original)
        }
    }
}

private extension ProfilePersonalWidgetSection {
    func profileWidgetJSON() throws -> JSONValue? {
        switch self {
        case let .cover(cover):
            guard cover.title.utf16.count <= 50, cover.subtitle.utf16.count <= 150 else {
                throw ChatProviderError.invalidRequest("Widget cover titles allow 50 characters and subtitles allow 150.")
            }
            guard !cover.isEmpty else { return nil }
            var value: [String: JSONValue] = ["type": .string("cover"), "title": .string(cover.title), "subtitle": .string(cover.subtitle)]
            if let image = cover.image { value["image"] = image.profileWidgetJSON }
            return .object(value)
        case let .fields(fields):
            guard fields.count <= 4 else { throw ChatProviderError.invalidRequest("A personal widget allows up to four fields.") }
            let result = try fields.compactMap { field -> JSONValue? in
                guard field.title.utf16.count <= 40, field.description.utf16.count <= 90 else {
                    throw ChatProviderError.invalidRequest("Widget field titles allow 40 characters and descriptions allow 90.")
                }
                guard !field.isEmpty else { return nil }
                var value: [String: JSONValue] = ["title": .string(field.title), "description": .string(field.description)]
                if let image = field.image { value["image"] = image.profileWidgetJSON }
                return .object(value)
            }
            return result.isEmpty ? nil : .object(["type": .string("fields"), "fields": .array(result)])
        }
    }
}

private extension ProfileWidgetImage {
    var profileWidgetJSON: JSONValue {
        switch reference {
        case let .pendingUpload(filename): .object(["filename": .string(filename)])
        case let .saved(id, width, height, isAnimated):
            .object(["file_id": .string(id), "width": .number(Double(width)), "height": .number(Double(height)), "is_animated": .bool(isAnimated)])
        }
    }
}
