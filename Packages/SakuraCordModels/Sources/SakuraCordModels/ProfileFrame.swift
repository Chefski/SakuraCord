import Foundation

public struct ProfileFrame: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var innerWidth: Double
    public var overflowTop: Double
    public var overflowBottom: Double
    public var overflowHorizontal: Double
    public var layers: [ProfileFrameLayer]

    public init(
        id: String, label: String, innerWidth: Double, overflowTop: Double,
        overflowBottom: Double, overflowHorizontal: Double, layers: [ProfileFrameLayer]
    ) {
        self.id = id
        self.label = label
        self.innerWidth = innerWidth
        self.overflowTop = overflowTop
        self.overflowBottom = overflowBottom
        self.overflowHorizontal = overflowHorizontal
        self.layers = layers
    }
}

public struct ProfileFrameLayer: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var type: String
    public var order: String
    public var anchor: String
    public var isResponsive: Bool
    public var staticURL: URL

    public init(id: String, type: String, order: String, anchor: String, isResponsive: Bool, staticURL: URL) {
        self.id = id
        self.type = type
        self.order = order
        self.anchor = anchor
        self.isResponsive = isResponsive
        self.staticURL = staticURL
    }
}
