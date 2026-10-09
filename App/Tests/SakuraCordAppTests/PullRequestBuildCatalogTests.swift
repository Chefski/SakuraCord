import Foundation
import Testing
@testable import SakuraCord

@Test("PR catalog decoding preserves immutable build identity and accepts published asset paths")
func pullRequestCatalogDecodesPublishedBuilds() throws {
    let builds = PullRequestBuildFixtures.builds
    var payload = try #require(JSONSerialization.jsonObject(with: catalogData(builds)) as? [String: Any])
    var entries = try #require(payload["builds"] as? [[String: Any]])
    // An older CI run retried later must not outrank the newest PR revision.
    entries[entries.count - 1]["createdAt"] = "2099-01-01T00:00:00Z"
    payload["builds"] = entries.reversed().map { $0 }
    let decoded = try PullRequestBuildClient.decode(JSONSerialization.data(withJSONObject: payload))
    #expect(decoded.map(\.id) == builds.map(\.id))
    #expect(decoded.first?.archiveURL == builds.first?.archiveURL)
    #expect(decoded.first?.commitSubject == builds.first?.commitSubject)
}

@Test("catalog rejects mismatched PR identity and cross-build or external assets", arguments: ["pullRequest", "appcastURL", "archiveURL", "symbolsURL"])
func pullRequestCatalogRejectsSubstitutedBuilds(_ field: String) throws {
    let builds = Array(PullRequestBuildFixtures.builds.prefix(2))
    var payload = try #require(JSONSerialization.jsonObject(with: catalogData(builds)) as? [String: Any])
    var entries = try #require(payload["builds"] as? [[String: Any]])
    switch field {
    case "pullRequest": entries[0][field] = builds[0].pullRequest + 1
    case "appcastURL": entries[0][field] = builds[1].appcastURL.absoluteString
    case "archiveURL": entries[0][field] = "https://example.com/SakuraCord.app.zip"
    default: entries[0][field] = builds[1].symbolsURL.absoluteString
    }
    payload["builds"] = entries
    let data = try JSONSerialization.data(withJSONObject: payload)
    #expect(throws: PullRequestBuildError.self) { try PullRequestBuildClient.decode(data) }
}

@Test("catalog rejects duplicate immutable build identities")
func pullRequestCatalogRejectsDuplicateBuilds() throws {
    let build = try #require(PullRequestBuildFixtures.builds.first)
    let data = try catalogData([build, build])
    #expect(throws: PullRequestBuildError.self) { try PullRequestBuildClient.decode(data) }
}

private func catalogData(_ builds: [PullRequestBuild]) throws -> Data {
    struct Catalog: Encodable {
        let schemaVersion = 1
        let builds: [PullRequestBuild]
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(Catalog(builds: builds))
}

@MainActor
@Test("historical commit searches select only matching install targets, including after refresh")
func historicalBuildSearchSelectsMatchingTarget() async throws {
    let store = PullRequestBuildStore(isPreview: true)
    await store.load()
    let historical = try #require(store.builds.first { $0.shortCommit == "a203df8" })
    store.selectedBuildID = store.selectedBuild?.id
    for query in [historical.shortCommit, historical.commitSubject] {
        store.search = query
        #expect(store.selectedBuild?.id == historical.id)
        #expect(store.selectedBuilds.map(\.id) == [historical.id])
        #expect(store.latestBuildID != historical.id)
        await store.load()
        #expect(store.selectedBuild?.id == historical.id)
    }
    store.search = "no matching commit"
    await store.load()
    #expect(store.selectedPullRequest == nil)
    #expect(store.selectedBuild == nil)
}
