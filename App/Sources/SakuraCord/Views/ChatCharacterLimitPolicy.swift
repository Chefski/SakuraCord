import Foundation

nonisolated enum ChatCharacterLimitPolicy {
    static let standardLimit = 2_000
    static let premiumLimit = 4_000

    static func limit(premiumType: Int?) -> Int {
        (premiumType ?? 0) > 0 ? premiumLimit : standardLimit
    }

    static func shouldShowCounter(characterCount: Int, limit: Int) -> Bool {
        characterCount >= limit - 200
    }

    static func shouldShowCounter(characterCount: Int, premiumType: Int?) -> Bool {
        shouldShowCounter(
            characterCount: characterCount,
            limit: limit(premiumType: premiumType)
        )
    }

    static func isWithinLimit(characterCount: Int, premiumType: Int?) -> Bool {
        characterCount <= limit(premiumType: premiumType)
    }
}
