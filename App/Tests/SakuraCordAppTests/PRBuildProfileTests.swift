import Foundation
import SakuraCordModels
import Testing
@testable import SakuraCord

@Test("PR preferences survive build updates without altering regular or another PR profile")
func previewPreferencesAreIsolated() {
    let run = Int.random(in: 1 ..< Int.max)
    let first = SakuraCordStorageProfile(infoDictionary: ["SakuraCordPullRequestBuildID": "pr-\(run)-run-1-attempt-1"])
    let updated = SakuraCordStorageProfile(infoDictionary: ["SakuraCordPullRequestBuildID": "pr-\(run)-run-2-attempt-1"])
    let second = SakuraCordStorageProfile(infoDictionary: ["SakuraCordPullRequestBuildID": "pr-\(run + 1)-run-1-attempt-1"])
    let firstDefaults = PRBuildProfile.defaults(for: first)
    let secondDefaults = PRBuildProfile.defaults(for: second)
    let key = "preview-isolation-\(UUID().uuidString)"
    defer {
        firstDefaults.removePersistentDomain(forName: first.preferencesSuiteName!)
        secondDefaults.removePersistentDomain(forName: second.preferencesSuiteName!)
    }

    firstDefaults.set("preview draft preference", forKey: key)
    #expect(PRBuildProfile.defaults(for: first).string(forKey: key) == "preview draft preference")
    #expect(PRBuildProfile.defaults(for: updated).string(forKey: key) == "preview draft preference")
    #expect(first.storageIdentifier == updated.storageIdentifier)
    #expect(secondDefaults.object(forKey: key) == nil)
    #expect(UserDefaults.standard.object(forKey: key) == nil)
    secondDefaults.set("different preview value", forKey: key)
    #expect(firstDefaults.string(forKey: key) == "preview draft preference")
}

@Test("malformed preview identity fails closed instead of writing regular preferences", arguments: ["", "../Accounts", "pr-0-run-1-attempt-1", "pr-1-run-1-attempt-1\n"])
func malformedPreviewIdentityCannotSelectRegularStorage(_ identifier: String) {
    let profile = SakuraCordStorageProfile(infoDictionary: ["SakuraCordPullRequestBuildID": identifier])
    let defaults = PRBuildProfile.defaults(for: profile)
    let key = "invalid-preview-isolation-\(UUID().uuidString)"
    defer { defaults.removeObject(forKey: key) }
    #expect(profile.previewIdentifier == "unrecognized-preview")
    defaults.set(true, forKey: key)
    #expect(UserDefaults.standard.object(forKey: key) == nil)
}

@Test("preview account metadata seeds once without copying settings or changing the source")
func previewAccountMetadataSeedsOnce() async {
    let source = InMemoryPreferences()
    let preview = InMemoryPreferences()
    let sourceStore = UserDefaultsSavedAccountStore(defaults: source, seedFrom: nil)
    await sourceStore.record(SavedAccount(accountID: "123", displayName: "Original account"))
    source.set("private theme choice", forKey: "theme")

    let previewStore = UserDefaultsSavedAccountStore(defaults: preview, seedFrom: source)
    #expect(await previewStore.preferredAccountID() == "123")
    #expect(previewStore.hasSavedAccounts)
    #expect(preview.object(forKey: "theme") == nil)

    await previewStore.remove(accountID: "123")
    #expect(await sourceStore.preferredAccountID() == "123")
    #expect(sourceStore.hasSavedAccounts)
    let reopenedPreview = UserDefaultsSavedAccountStore(defaults: preview, seedFrom: source)
    #expect(!reopenedPreview.hasSavedAccounts)
    #expect(await reopenedPreview.preferredAccountID() == nil)
}
