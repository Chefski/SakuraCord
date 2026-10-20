import SakuraCordModels
import SwiftUI

// The workspace's toolbar actions, shared by the window toolbar and the
// column-owned toolbar (`WorkspaceTitlebar`).

struct InboxToolbarButton: View {
    let model: AppModel
    /// Off for a copy of the button that is out of view, so the panel opens
    /// from the visible one only.
    var presentsPanel = true

    var body: some View {
        Button {
            if model.inbox.isPresented { model.dismissInbox() } else { model.presentInbox() }
        } label: {
            Label("Inbox", systemImage: model.inbox.isPresented ? "tray.fill" : "tray")
                .symbolVariant(.none)
                .animation(.smooth(duration: 0.24), value: model.inbox.isPresented)
        }
        .help("Inbox")
        .background {
            StableAnchoredPopoverPresenter(
                isPresented: presentsPanel && model.inbox.isPresented,
                configuration: .toolbarPanel,
                onDismiss: model.dismissInbox,
                onWillDismiss: model.dismissInbox
            ) { InboxPopoverView(model: model) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PinnedMessagesToolbarButton: View {
    let model: AppModel
    let channelID: ChannelID
    var presentsPanel = true

    var body: some View {
        let isPresented = model.pinnedMessages.isPresented && model.pinnedMessages.channelID == channelID
        Button {
            if isPresented {
                model.dismissPinnedMessages()
            } else {
                model.presentPinnedMessages(channelID: channelID)
            }
        } label: {
            Label("Pinned Messages", systemImage: isPresented ? "pin.fill" : "pin")
                .symbolVariant(.none)
                .animation(.smooth(duration: 0.24), value: isPresented)
        }
        .help("Pinned Messages")
        .background {
            StableAnchoredPopoverPresenter(
                isPresented: presentsPanel && isPresented,
                configuration: .toolbarPanel,
                onDismiss: model.dismissPinnedMessages,
                onWillDismiss: model.dismissPinnedMessages
            ) {
                PinnedMessagesPopoverView(model: model)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ThreadsToolbarButton: View {
    let model: AppModel
    var presentsPanel = true

    var body: some View {
        Button(action: model.toggleThreadBrowser) {
            Label {
                Text("Threads")
            } icon: {
                SakuraCordSystemSymbol.swiftUIImage(named: SakuraCordSystemSymbol.thread)
            }
        }
        .help("Threads")
        .background {
            StableAnchoredPopoverPresenter(
                isPresented: presentsPanel && model.threadBrowser.isPresented,
                configuration: .toolbarPanel,
                onDismiss: model.dismissThreadBrowser,
                onWillDismiss: model.dismissThreadBrowser
            ) { ThreadBrowserPopoverView(model: model) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MemberInspectorToolbarButton: View {
    let model: AppModel

    var body: some View {
        let isDirectMessage = model.selectedChannel?.kind == .directMessage
        let isGroup = model.selectedChannel?.kind == .groupDirectMessage
        let isShown = model.workspacePresentation.supplementaryPane == .memberInspector
        Button {
            model.toggleMemberInspector()
        } label: {
            Label(
                isDirectMessage || isGroup ? "People" : "Members",
                systemImage: isDirectMessage
                    ? (isShown ? "person.fill" : "person")
                    : (isShown ? "person.2.fill" : "person.2")
            )
            .symbolVariant(.none)
            .animation(.smooth(duration: 0.24), value: isShown)
        }
    }
}

/// A side chat's actions: Add to Channel List, Follow, its menu and Close.
struct SideConversationToolbarActions: View {
    let model: AppModel
    let conversation: SideConversation

    var body: some View {
        let capabilities = conversation.capabilities
        // One group, as the toolbar draws adjacent items: on one capsule.
        HStack(spacing: 0) {
            if capabilities.canAddToChannelList, let channel = model.customizationPreviewChannel,
               !model.isChannelSelected(channel), let guildID = channel.guildID
            {
                Button("Add to Channel List", systemImage: "plus") {
                    model.setChannelSelected(true, channelID: channel.id, guildID: guildID)
                }
                .help("Add to Channel List")
            }
            if case .thread(let thread, _) = conversation {
                if ForumPostFollowToolbarButton.isOffered(model: model, thread: thread) {
                    ForumPostFollowToolbarButton(model: model, thread: thread, surface: .forumPostHeader)
                }
                ThreadActionsToolbarMenu(model: model, thread: thread, surface: .sidePane)
            }
            Button {
                model.closeSideConversation()
            } label: {
                Label("Close conversation", systemImage: "xmark")
            }
            .help(capabilities.closeHelp)
            .keyboardShortcut(model.guildWorkspacePage == .guide ? .cancelAction : nil)
        }
        .titlebarButtons(grouped: true)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

/// A side chat's title in the column-owned toolbar: it fills the pane up to
/// the pane's actions.
struct SideConversationTitlebarTitle: View {
    let label: SideConversationLabel

    var body: some View {
        ConversationToolbarLabel(
            title: label.title,
            systemImage: label.systemImage,
            subtitle: nil,
            textSize: InterfaceTypographyMetrics.interfaceTextSize
        )
        .padding(.horizontal, 8)
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: Capsule())
    }
}

extension View {
    /// Buttons as the window toolbar draws them: icons on their own glass,
    /// or on their group's.
    func titlebarButtons(grouped: Bool = false) -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(TitlebarGlassButtonStyle(hasOwnGlass: !grouped))
            .toggleStyle(.button)
    }
}

/// The window toolbar's icon button: a glass circle with the item's icon.
struct TitlebarGlassButtonStyle: ButtonStyle {
    var hasOwnGlass = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .imageScale(.medium)
            // The toolbar draws its icons slightly translucent, over glass.
            .foregroundStyle(.primary.opacity(0.88))
            // As wide as the toolbar's own: its icon's width, inset, at least
            // a circle.
            .padding(.horizontal, 7)
            .frame(minWidth: 36, minHeight: 36)
            .contentShape(Capsule())
            .glassEffect(hasOwnGlass ? .regular.interactive() : .identity, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
