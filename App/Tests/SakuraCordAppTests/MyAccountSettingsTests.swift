@testable import SakuraCord
import DiscordProtocol
import Foundation
import Testing

@Test func `Settings account inspection selection is independent and repairs removed accounts`() {
    let first = SavedAccount(accountID: "100", displayName: "First")
    let second = SavedAccount(accountID: "200", displayName: "Second")
    let accounts = [first, second]

    #expect(
        SettingsAccountSelectionPolicy.accountID(
            storedAccountID: second.accountID,
            activeAccountID: first.accountID,
            accounts: accounts
        ) == second.accountID
    )
    #expect(
        SettingsAccountSelectionPolicy.accountID(
            storedAccountID: "removed",
            activeAccountID: first.accountID,
            accounts: accounts
        ) == first.accountID
    )
    #expect(
        SettingsAccountSelectionPolicy.accountID(
            storedAccountID: "removed",
            activeAccountID: "signed-out",
            accounts: accounts
        ) == first.accountID
    )
    #expect(
        SettingsAccountSelectionPolicy.accountID(
            storedAccountID: "removed",
            activeAccountID: nil,
            accounts: []
        ) == nil
    )
}
