import Foundation

public struct ProfileNameFont: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var postScriptName: String
    public var assetURL: URL?
    public var letterSpacing: Double
    public var isNew: Bool

    public init(id: Int, name: String, postScriptName: String, assetURL: URL?, letterSpacing: Double = 0, isNew: Bool = false) {
        self.id = id
        self.name = name
        self.postScriptName = postScriptName
        self.assetURL = assetURL
        self.letterSpacing = letterSpacing
        self.isNew = isNew
    }
}

public enum ProfileNameEffect: Int, CaseIterable, Identifiable, Sendable {
    case solid = 1
    case gradient = 2
    case neon = 3
    case toon = 4
    case pop = 5
    case gummy = 8
    case prism = 7

    public var id: Int { rawValue }
}

public struct ProfileNameStyleCatalog: Sendable {
    public var fonts: [ProfileNameFont]
    public var solidColors: [UInt32]
    public var gradients: [[UInt32]]
    public var gummyPalettes: [[UInt32]]
    public var prismPalettes: [[UInt32]]

    public init(fonts: [ProfileNameFont], solidColors: [UInt32], gradients: [[UInt32]], gummyPalettes: [[UInt32]], prismPalettes: [[UInt32]]) {
        self.fonts = fonts
        self.solidColors = solidColors
        self.gradients = gradients
        self.gummyPalettes = gummyPalettes
        self.prismPalettes = prismPalettes
    }
}
