import AppKit
import SakuraCordModels
import SwiftUI

struct InboxForumPostView: View {
    let post: ForumPost
    let model: AppModel

    var body: some View {
        // The entry opens the post from a background button so the preview
        // can take clicks on hidden spoilers, which reveal them in place.
        VStack(alignment: .leading, spacing: InterfaceScale.metric(5)) {
            Text(post.thread.name).font(.interface(.headline)).lineLimit(1)
                .allowsHitTesting(false)
            if let message = post.firstMessage {
                ForumPostPreviewText(
                    model: model,
                    message: message,
                    maximumNumberOfLines: 1,
                    isEmphasized: false,
                    textStyle: .callout
                )
            } else {
                Text("\(post.thread.messageCount) messages")
                    .font(.interface(.caption)).foregroundStyle(.secondary)
                    .accessibilityLabel("\(post.thread.messageCount) replies")
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, InterfaceScale.metric(16))
        .frame(height: InboxRowMetrics.forumPostHeight)
        .background {
            Button { model.openInboxForumPost(post) } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(PopoverRowButtonStyle())
            .accessibilityLabel(post.thread.name)
            .accessibilityHint("Opens this post")
        }
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, InterfaceScale.metric(12)) }
        .help("Open post")
    }
}

extension NativeTimelineCanvasView {
    func reconcileInboxForumPosts() {
        var desired: [ChannelID: (ForumPost, CGRect)] = [:]
        forEachDisplayedRow(in: visibleRect) { index in
            if case let .inboxForumPost(post) = items[index] {
                desired[post.id] = (post, CGRect(x: 0, y: displayedRowOrigin(at: index), width: bounds.width, height: InboxRowMetrics.forumPostHeight))
            }
        }
        for id in Array(inboxForumPostHosts.keys) where desired[id] == nil {
            inboxForumPostHosts.removeValue(forKey: id)?.removeFromSuperview()
        }
        guard let model else { return }
        for (id, value) in desired {
            let host: NSHostingView<InboxForumPostView>
            if let existing = inboxForumPostHosts[id] {
                host = existing
                if host.rootView.post != value.0 { host.rootView = InboxForumPostView(post: value.0, model: model) }
            } else {
                host = NSHostingView(rootView: InboxForumPostView(post: value.0, model: model))
                inboxForumPostHosts[id] = host
                addSubview(host)
            }
            host.frame = value.1
        }
    }
}
