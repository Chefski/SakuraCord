import AppKit
import SakuraCordModels
import SwiftUI

struct InboxForumPostView: View {
    let post: ForumPost
    let model: AppModel

    var body: some View {
        Button { model.openInboxForumPost(post) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(post.thread.name).font(.headline).lineLimit(1)
                if let message = post.firstMessage {
                    Text(MessageReplySummary.text(
                        content: message.content,
                        mentionLabel: MessageMentionResolver(model: model, message: message).label
                    )).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text("\(post.thread.messageCount) messages")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("\(post.thread.messageCount) replies")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(height: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverRowButtonStyle())
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 12) }
        .help("Open post")
    }
}

extension NativeTimelineCanvasView {
    func reconcileInboxForumPosts() {
        var desired: [ChannelID: (ForumPost, CGRect)] = [:]
        if let first = rowIndex(at: max(0, visibleRect.minY)) {
            var index = first
            while items.indices.contains(index), displayedRowOrigin(at: index) < visibleRect.maxY {
                if case let .inboxForumPost(post) = items[index] {
                    desired[post.id] = (post, CGRect(x: 0, y: displayedRowOrigin(at: index), width: bounds.width, height: 88))
                }
                index += 1
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
