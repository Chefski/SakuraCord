import SakuraCordModels
import SwiftUI

/// The open thread's overflow menu in the window toolbar: the side chat's
/// pane menu, or the full view's.
struct ThreadActionsToolbarMenu: View {
    let model: AppModel
    let thread: MessageThreadSummary
    let surface: ThreadActionSurface

    var body: some View {
        Menu {
            ThreadActionsMenuContent(actionsMenu: ThreadActionsMenu(model: model, thread: thread, surface: surface))
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
        .help(model.isForumThread(thread) ? "More post actions" : "More thread actions")
    }
}

/// The open forum post's Follow toggle, as in the first-party post header.
struct ForumPostFollowToolbarButton: View {
    let model: AppModel
    let thread: MessageThreadSummary
    let surface: ThreadActionSurface

    var body: some View {
        let thread = model.currentThreadSummary(thread)
        let isFollowing = thread.notificationSettings != nil
        Button {
            model.setThreadMembership(thread, isJoined: !isFollowing, surface: surface)
        } label: {
            Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "checkmark" : "plus")
                .labelStyle(.titleAndIcon)
        }
        .disabled(!model.threadActionPolicy(thread).canChangeMembership)
        .help("Add this post to your channel list and receive notifications about it.")
    }

    static func isOffered(model: AppModel, thread: MessageThreadSummary) -> Bool {
        model.isForumThread(thread) && model.threadActionPolicy(thread).canRead
    }
}
