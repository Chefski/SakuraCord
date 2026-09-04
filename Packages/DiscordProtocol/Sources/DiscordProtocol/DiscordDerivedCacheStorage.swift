import Foundation

/// Disposable account-scoped search/catalog metadata. Message bodies and
/// credentials never enter these files. Draft storage has a separate owner.
public enum DiscordDerivedCacheStorage {
    public static func remove(accountID: String, cacheRoot: URL? = nil) async throws {
        let root = cacheRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let root else { return }
        let safeID = accountID.replacingOccurrences(
            of: #"[^A-Za-z0-9_.-]"#, with: "-", options: .regularExpression
        )
        guard !safeID.isEmpty, safeID != ".", safeID != ".." else {
            throw ChatProviderError.invalidRequest("Invalid account cache identifier.")
        }
        let directory = root.appending(path: "dev.sakuracord.SakuraCord", directoryHint: .isDirectory)
        let urls = [
            directory.appending(path: "ForwardSearchPeople/\(safeID).json"),
            directory.appending(path: "QuickSwitcherChannelStore/\(safeID).json"),
            directory.appending(path: "EmojiCache/\(safeID)", directoryHint: .isDirectory)
        ]
        try await Task.detached(priority: .utility) {
            for url in urls where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }.value
    }
}
