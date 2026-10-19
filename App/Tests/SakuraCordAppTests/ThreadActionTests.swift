import Foundation
import SakuraCordModels
import Testing
@testable import SakuraCord

@MainActor
@Test func `thread actions offer notification settings only once joined and invoke the model`() async throws {
    let model = AppModel(launchMode: .offlineTesting)
    await model.start()
    let forum = try #require(model.snapshot?.channels.first { $0.kind == .forum })
    model.selectedChannelID = forum.id
    #expect(await until { model.hasLoadedForumPosts })
    let post = try #require(model.forumCataloguePosts.first {
        !$0.thread.isArchived && !$0.thread.isLocked && $0.thread.notificationSettings == nil
    })
    func entries() -> [String: ThreadMenuEntry] {
        let menu = ThreadActionsMenu(model: model, thread: post.thread, surface: .forumCard, offersTags: true)
        return Dictionary(menu.sections.flatMap { $0 }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    func invoke(_ id: String) throws {
        guard case .action(let action)? = entries()[id]?.content else { throw CancellationError() }
        action()
    }

    // The offline account manages threads, so moderation is offered.
    #expect(["membership", "rename", ThreadActionsMenu.tagsSlotID, "archive", "lock", "pin", "delete"]
        .allSatisfy { entries()[$0] != nil })
    #expect(entries()["mute"] == nil && entries()["notifications"] == nil)

    try invoke("membership")
    #expect(await until {
        model.forumCataloguePosts.first { $0.id == post.id }?.thread.notificationSettings != nil
    })
    #expect(entries()["mute"] != nil && entries()["notifications"] != nil)
    try invoke("rename")
    #expect(model.threadActions.renaming?.id == post.id)
}
