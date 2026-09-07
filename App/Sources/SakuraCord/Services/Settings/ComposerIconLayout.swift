import Foundation

nonisolated enum ComposerIcon: String, CaseIterable, Codable, Identifiable, Sendable {
    case gif
    case sticker
    case emoji

    var id: Self { self }
}

nonisolated struct ComposerIconLayout: Codable, Equatable, Sendable {
    static let defaults = Self(order: ComposerIcon.allCases)

    private(set) var order: [ComposerIcon]

    init(order: [ComposerIcon]) {
        var seen: Set<ComposerIcon> = []
        self.order = order.filter { seen.insert($0).inserted }
        self.order += ComposerIcon.allCases.filter { !seen.contains($0) }
    }

    init(storageValue: String) {
        if let decoded = try? JSONDecoder().decode(Self.self, from: Data(storageValue.utf8)) {
            self.init(order: decoded.order)
        } else {
            self = .defaults
        }
    }

    var storageValue: String {
        String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? ""
    }

    mutating func move(_ icons: [ComposerIcon], before destination: ComposerIcon?) {
        let moving = order.filter { icons.contains($0) }
        guard !moving.isEmpty, destination.map({ !moving.contains($0) }) ?? true else { return }
        order.removeAll { moving.contains($0) }
        let index = destination.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
        order.insert(contentsOf: moving, at: index)
    }
}
