import Foundation

public enum ProfileCollectibleKind: Int, CaseIterable, Codable, Sendable {
    case avatarDecoration = 0
    case effect = 1
    case nameplate = 2
    case frame = 3
}

public enum ProfileCollectibleArtwork: Hashable, Sendable {
    case avatarDecoration(URL)
    case effect(ProfileEffect)
    case nameplate(Nameplate)
    case frame(ProfileFrame)
}

public struct ProfileCollectibleItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ProfileCollectibleKind
    public var label: String
    public var artwork: ProfileCollectibleArtwork

    public init(id: String, kind: ProfileCollectibleKind, label: String, artwork: ProfileCollectibleArtwork) {
        self.id = id
        self.kind = kind
        self.label = label
        self.artwork = artwork
    }
}

public struct ProfileCollectibleProduct: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var categoryID: String?
    public var type: Int
    public var premiumType: Int
    public var purchaseType: Int?
    public var items: [ProfileCollectibleItem]
    public var variants: [ProfileCollectibleProduct]
    public var bundledProducts: [ProfileCollectibleProduct]
    public var variantLabel: String?
    public var variantColor: String?
    public var baseVariantID: String?
    public var purchasedAt: Date?
    public var expiresAt: Date?

    public init(
        id: String, name: String, summary: String, categoryID: String? = nil,
        type: Int, premiumType: Int, purchaseType: Int? = nil, items: [ProfileCollectibleItem] = [],
        variants: [ProfileCollectibleProduct] = [], bundledProducts: [ProfileCollectibleProduct] = [],
        variantLabel: String? = nil, variantColor: String? = nil, baseVariantID: String? = nil,
        purchasedAt: Date? = nil, expiresAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.categoryID = categoryID
        self.type = type
        self.premiumType = premiumType
        self.purchaseType = purchaseType
        self.items = items
        self.variants = variants
        self.bundledProducts = bundledProducts
        self.variantLabel = variantLabel
        self.variantColor = variantColor
        self.baseVariantID = baseVariantID
        self.purchasedAt = purchasedAt
        self.expiresAt = expiresAt
    }
}

public struct ProfileCollectibleCategory: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var bannerURL: URL?
    public var products: [ProfileCollectibleProduct]

    public init(id: String, name: String, summary: String, bannerURL: URL?, products: [ProfileCollectibleProduct]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.bannerURL = bannerURL
        self.products = products
    }
}

public struct ProfileCollectibleInventory: Hashable, Sendable {
    public var categories: [ProfileCollectibleCategory] { didSet { rebuildIndex() } }
    public var purchases: [ProfileCollectibleProduct] { didSet { rebuildIndex() } }
    public private(set) var catalogueProducts: [ProfileCollectibleProduct] = []
    private var purchasesByID: [String: [ProfileCollectibleProduct]] = [:]
    private var productsByItemID: [String: ProfileCollectibleProduct] = [:]
    private var itemsByKind: [ProfileCollectibleKind: [ProfileCollectibleItem]] = [:]

    public init(categories: [ProfileCollectibleCategory], purchases: [ProfileCollectibleProduct]) {
        self.categories = categories
        self.purchases = purchases
        rebuildIndex()
    }

    /// Catalogue membership and ownership are independent. A variant group never
    /// grants its siblings, and expired purchases cannot authorize a save.
    public func owns(itemID: String, at date: Date = .now) -> Bool {
        purchase(itemID: itemID, at: date) != nil
    }

    public func purchase(itemID: String, at date: Date = .now) -> ProfileCollectibleProduct? {
        purchasesByID[itemID]?.first {
            $0.items.contains { $0.id == itemID }
                && ($0.expiresAt.map { $0 > date } ?? true)
        }
    }

    /// The official picker classifies owned products by purchase_type (7 is a
    /// premium purchase), not the catalogue's premium_type. A subscription alone
    /// does not grant an unclaimed product.
    public func canUse(itemID: String, hasFullNitro: Bool, at date: Date = .now) -> Bool {
        guard let purchase = purchase(itemID: itemID, at: date) else { return false }
        return purchase.purchaseType != 7 || hasFullNitro
    }

    public func requiresNitro(itemID: String) -> Bool {
        if let purchase = purchasesByID[itemID]?.first { return purchase.purchaseType == 7 }
        return product(itemID: itemID).map { $0.premiumType != 0 } ?? false
    }

    public func product(itemID: String) -> ProfileCollectibleProduct? {
        productsByItemID[itemID]
    }

    public func item(id: String) -> ProfileCollectibleItem? {
        product(itemID: id)?.items.first { $0.id == id }
    }

    public func items(of kind: ProfileCollectibleKind) -> [ProfileCollectibleItem] {
        itemsByKind[kind] ?? []
    }

    /// Index on inventory changes, rather than flattening the whole catalogue
    /// for each entitlement check and tile during SwiftUI body evaluation.
    private mutating func rebuildIndex() {
        func flatten(_ products: [ProfileCollectibleProduct]) -> [ProfileCollectibleProduct] {
            products.flatMap { $0.variants.isEmpty ? [$0] : flatten($0.variants) }
        }
        catalogueProducts = flatten(categories.flatMap(\.products))
        purchasesByID = Dictionary(grouping: purchases, by: \.id)
        productsByItemID = [:]
        for product in purchases {
            for item in product.items where item.id == product.id && productsByItemID[item.id] == nil {
                productsByItemID[item.id] = product
            }
        }
        for product in catalogueProducts {
            for item in product.items where productsByItemID[item.id] == nil { productsByItemID[item.id] = product }
        }
        itemsByKind = [:]
        var seen = Set<String>()
        for product in purchases + catalogueProducts {
            for item in product.items where seen.insert(item.id).inserted {
                itemsByKind[item.kind, default: []].append(item)
            }
        }
    }
}
