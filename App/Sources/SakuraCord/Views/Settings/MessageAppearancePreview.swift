import SakuraCordModels
import SwiftUI

struct MessageAppearancePreview: View {
    let appearance: AppearanceSettingsSnapshot
    let interface: InterfaceSettingsSnapshot
    let accessibility: AccessibilitySettingsSnapshot
    let chat: ChatSettingsSnapshot

    @State private var preview: AppModel?
    @State private var scrollRequest: MessageTimelineScrollRequest?

    var body: some View {
        Group {
            if let preview {
                NativeMessageTimelineView(
                    model: preview,
                    conversation: .channel(MessageAppearancePreviewContent.channelID),
                    beginning: nil,
                    firstMessageStartsDayOverride: false,
                    hasMoreMessages: false,
                    isLoadingEarlier: false,
                    bottomContentInset: 12,
                    unreadMessageID: nil,
                    highlightedMessageID: preview.replyingTo?.id,
                    initialScrollTarget: preview.messageRows.first.map {
                        .message($0.id, anchor: .top)
                    },
                    scrollRequest: scrollRequest,
                    runsPerformanceAutoScroll: false,
                    loadEarlier: {},
                    openReply: { messageID in
                        scrollRequest = MessageTimelineScrollRequest(
                            target: .message(messageID, anchor: .center)
                        )
                    },
                    onScrollActivityChange: { _ in },
                    onScrollStateChange: { _ in },
                    onUserScrollBegan: {},
                    onUserScrollEnded: { _ in }
                )
                .background {
                    MediaViewerWindowOverlay(
                        presentation: preview.mediaViewerPresentation,
                        dismiss: { preview.mediaViewerPresentation = nil }
                    )
                    .frame(width: 0, height: 0)
                }
            } else {
                Color.clear
            }
        }
        .frame(height: 280)
        .background { SakuraCordThemeBackground() }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Message style preview")
        .task {
            guard preview == nil else { return }
            preview = MessageAppearancePreviewContent.makeModel()
            updatePresentation()
        }
        .onChange(of: appearance) { updatePresentation() }
        .onChange(of: interface) { updatePresentation() }
        .onChange(of: accessibility) { updatePresentation() }
        .onChange(of: chat) { updatePresentation() }
    }

    private func updatePresentation() {
        guard let preview else { return }
        // Mirror rendering preferences without writing settings or starting a session.
        preview.appearanceSettings = appearance
        preview.interfaceSettings = interface
        preview.accessibilitySettings = accessibility
        preview.chatSettings = chat
        preview.invalidateTimelinePresentation()
    }
}
