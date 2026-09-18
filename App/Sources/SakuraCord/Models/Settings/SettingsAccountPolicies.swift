import DiscordProtocol

nonisolated enum SettingsAccountSelectionPolicy {
    static func accountID(
        storedAccountID: String,
        activeAccountID: String?,
        accounts: [SavedAccount]
    ) -> String? {
        if accounts.contains(where: { $0.accountID == storedAccountID }) {
            return storedAccountID
        }
        if let activeAccountID,
           accounts.contains(where: { $0.accountID == activeAccountID })
        {
            return activeAccountID
        }
        return accounts.first?.accountID
    }
}
