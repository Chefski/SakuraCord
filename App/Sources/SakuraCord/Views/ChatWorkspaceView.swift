import SakuraCordModels
import SwiftUI

struct ChatWorkspaceView: View {
    let model: AppModel
    @Binding var presentsForumComposer: Bool
    let toolbarSearchFieldMetrics: ToolbarSearchFieldMetrics
    /// The side chat pane's width, which the conversation keeps while a
    /// thread widens over it.
    @State private var paneWidth: CGFloat = 0
    @State private var workspaceWidth: CGFloat = 0
    @State private var conversationWidth: CGFloat = 0
    @State private var inspectorWidth: CGFloat = 0

    /// Where the pane's leading edge was, relative to the workspace.
    private var paneLeadingEdge: CGFloat {
        max(0, workspaceWidth - paneWidth)
    }

    @ViewBuilder var body: some View {
        let presentation = model.workspacePresentation
        Group {
            switch presentation.primary {
            case .guildPage(let page):
                if let guildID = model.selectedGuildID {
                    guildWorkspace(page, guildID: guildID, presentation: presentation)
                }
            case .friends:
                FriendsView(model: model)
                    .id("friends-\(model.currentUser?.id.description ?? "")")
            case .channel, .fullWidthThread:
                conversation(presentation)
            }
        }
        .windowModal(
            item: Binding(
                get: { model.interactionModalForm },
                set: {
                    if $0 == nil {
                        model.dismissInteractionModal()
                    }
                }
            ),
            cornerRadius: InterfaceScale.metric(32),
            cornerStyle: .circular
        ) { form in
            InteractionModalView(model: model, form: form)
                .windowModalDismissDisabled(form.isSubmitting)
        }
    }

    private func guildWorkspace(
        _ page: GuildWorkspacePage,
        guildID: GuildID,
        presentation: WorkspacePresentation
    ) -> some View {
        HStack(spacing: 0) {
            Group {
                switch page {
                case .channelsAndRoles: GuildCustomizationView(model: model, guildID: guildID)
                    .id("customization-\(guildID)-\(model.currentUser?.id.description ?? "")")
                case .guide: GuildGuideView(model: model, guildID: guildID)
                    .id("guide-\(guildID)-\(model.currentUser?.id.description ?? "")")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let conversation = presentation.paneSideConversation {
                SideConversationView(model: model, conversation: conversation)
                    .workspaceMotionProbe("pane")
                    .id(conversation.motionIdentity)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func conversation(_ presentation: WorkspacePresentation) -> some View {
        let motion = WorkspaceMotionPhase.shared
        let widening = motion.widening
        let channelContent: WorkspacePresentation.ChannelContent? =
            if case .channel(let content) = presentation.primary { content } else { widening?.channel }
        // A thread keeps one view, and its timeline, between the pane and
        // full width.
        let fullWidthThread = presentation.primary == .fullWidthThread
            ? model.sideConversations.thread.map { WorkspaceTrailingColumn(.sideConversation($0)) }
            : nil
        let trailing = WorkspaceTrailingColumn(presentation)
        // Departing columns come first, so a column that arrives covers them.
        let columns = motion.departing.filter { $0.id != trailing?.id && $0.id != fullWidthThread?.id }
            + [fullWidthThread, trailing].compactMap(\.self)
        let showsInspector = if case .inspector = trailing?.content { true } else { false }
        let columnsLayout = WorkspaceColumnsLayout(
            showsSideConversation: fullWidthThread != nil || presentation.paneSideConversation != nil,
            sideConversationIsFullWidth: fullWidthThread != nil,
            showsInspector: showsInspector,
            paneWidth: paneWidth,
            conversationWidthLimit: motion.isMoving ? conversationWidth : nil
        )
        return columnsLayout {
            if let channelContent {
                ChatWorkspacePrimaryContent(
                    model: model,
                    content: channelContent,
                    presentsForumComposer: $presentsForumComposer
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .workspaceMotionProbe("primary")
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { conversationWidth = $0 }
                // A widening thread slides over the conversation, which is
                // gone by the time it is covered.
                .opacity(widening?.hasArrived == true ? 0 : 1)
                .animation(.easeOut(duration: 0.12), value: widening?.hasArrived)
                .layoutValue(key: WorkspaceColumn.self, value: .conversation)
            }

            ForEach(columns) { column in
                trailingColumn(column, motion: motion)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { workspaceWidth = $0 }
        .onChange(of: model.selectedChannelID) { _, channelID in
            guard let channelID else {
                AppPerformanceSignposts.cancelConversationNavigation()
                return
            }
            AppPerformanceSignposts.ensureConversationNavigation(
                to: channelID
            )
        }
    }

    @ViewBuilder
    private func trailingColumn(_ column: WorkspaceTrailingColumn, motion: WorkspaceMotionPhase) -> some View {
        switch column.content {
        case .sideConversation(let conversation):
            SideConversationView(model: model, conversation: conversation)
                .workspaceMotionProbe("pane")
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    // A leaving pane loses its content and shrinks to its divider.
                    if !conversation.isFullWidth, !motion.departing.contains(column) { paneWidth = width }
                }
                .offset(x: offset(of: column, motion: motion))
                .layoutValue(key: WorkspaceColumn.self, value: .sideConversation)
        case .inspector(let pane):
            ChatWorkspaceSupplementaryContent(
                model: model,
                pane: pane,
                toolbarSearchFieldMetrics: toolbarSearchFieldMetrics
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                if !motion.departing.contains(column) { inspectorWidth = width }
            }
            .workspaceMotionProbe(pane.motionProbeName)
            .offset(x: offset(of: column, motion: motion))
            .layoutValue(key: WorkspaceColumn.self, value: .inspector)
        }
    }

    private func width(of column: WorkspaceTrailingColumn) -> CGFloat {
        switch column.content {
        case .sideConversation: max(paneWidth, InterfaceScale.metric(340))
        case .inspector: max(inspectorWidth, ChatChromeMetrics.memberListWidth)
        }
    }

    /// How far a moving column sits from its place: beyond the trailing edge
    /// as it arrives or leaves, or at the pane's edge as a thread widens.
    private func offset(of column: WorkspaceTrailingColumn, motion: WorkspaceMotionPhase) -> CGFloat {
        if case .sideConversation(let conversation) = column.content, conversation.isFullWidth {
            return motion.widening?.hasArrived == false ? paneLeadingEdge : 0
        }
        return width(of: column) * (1 - motion.reveal(of: column.id))
    }
}

private struct ChatWorkspacePrimaryContent: View {
    let model: AppModel
    let content: WorkspacePresentation.ChannelContent
    @Binding var presentsForumComposer: Bool

    var body: some View {
        switch content {
        case .chat:
            if let channel = model.selectedChannel,
               channel.kind == .directMessage || channel.kind == .groupDirectMessage,
               model.privateCall(in: channel.id) != nil
                    || model.activeVoiceChannel?.id == channel.id
            {
                DirectMessageCallWorkspace(model: model, channel: channel)
                    .background {
                        nonTimelineFrameReporter(channel.id)
                    }
            } else {
                ChatDetailView(model: model)
            }
        case .forum:
            ForumChannelView(model: model, presentsComposer: $presentsForumComposer)
                .background {
                    if let channelID = model.selectedChannelID {
                        nonTimelineFrameReporter(channelID)
                    }
                }
        case .voice:
            VoiceChannelView(model: model)
                .background {
                    if let channelID = model.selectedChannelID {
                        nonTimelineFrameReporter(channelID)
                    }
                }
        }
    }

    private func nonTimelineFrameReporter(
        _ channelID: ChannelID
    ) -> some View {
        DisplayCompleteFrameReporter(
            presentationID: channelID.rawValue
        ) {
            guard model.selectedChannelID == channelID else { return }
            AppPerformanceSignposts.reportNonTimelineWorkspaceFrame()
            AppPerformanceSignposts.reportConversationFirstFrame(
                channelID: channelID
            )
        }
        .frame(width: 1, height: 1)
    }
}

private struct ChatWorkspaceSupplementaryContent: View {
    let model: AppModel
    let pane: SupplementaryPane
    let toolbarSearchFieldMetrics: ToolbarSearchFieldMetrics

    var body: some View {
        switch pane {
        case .sideConversation(let conversation):
            SideConversationView(model: model, conversation: conversation)
        case .memberInspector:
            HStack(spacing: 0) {
                if model.selectedChannel?.kind != .directMessage {
                    Divider()
                        .ignoresSafeArea(.container, edges: .top)
                }
                memberInspector
            }
        case .messageSearch:
            HStack(spacing: 0) {
                Divider()
                    .ignoresSafeArea(.container, edges: .top)
                if toolbarSearchFieldMetrics.isValid {
                    MessageSearchPanelView(model: model)
                        .id(ObjectIdentifier(model.messageSearch))
                        .frame(width: ChatChromeMetrics.memberListWidth)
                        .frame(maxHeight: .infinity)
                        .reportsSupplementaryPaneFrame()
                }
            }
        }
    }

    @ViewBuilder private var memberInspector: some View {
        let userContext = UserMenuContext(guildID: model.selectedGuildID, channelID: model.selectedChannelID)
        if model.isThreadFullWidth, let thread = model.openThread,
           model.openThreadParentChannel?.kind != .announcement {
            ThreadMemberInspectorView(model: model, thread: thread)
                .frame(width: ChatChromeMetrics.memberListWidth)
                .frame(maxHeight: .infinity)
        } else if let channel = model.selectedChannel,
           channel.kind == .directMessage,
           let recipient = channel.recipients.first
        {
            DirectMessageProfileInspector(
                model: model,
                recipient: recipient
            )
        } else {
            MemberInspectorView(
                sections: model.directMessageInspectorSections,
                customEmojiURLsByID: model.customEmojiURLsByID,
                profilePresentation:
                    model.liveProfilePresentation(for: .inspector),
                isProfilePresented: model.isInspectorProfilePresented,
                selectMember: model.selectMember,
                dismissProfile: model.dismissInspectorProfile,
                viewportIdentity: model.selectedChannelID,
                presentation: NativeMemberListPresentation(
                    roleColorDisplay: model.accessibilitySettings.roleColorDisplay
                ),
                openProfile: model.expandProfile,
                sendProfileMessage: model.sendProfileMessage,
                userMenu: { UserContextMenu.make(for: $0.user, context: userContext, model: model) },
                userAccessibilityActions: { UserContextMenu.accessibilityActions(for: $0.user, context: userContext, model: model) },
                updateViewport: model.updateMemberListViewport
            )
            .frame(width: ChatChromeMetrics.memberListWidth)
            .frame(maxHeight: .infinity)
        }
    }
}

private struct DirectMessageProfileInspector: View {
    let model: AppModel
    let recipient: User

    var body: some View {
        Group {
            if let presentation = model.liveProfilePresentation(for: .inspector),
               presentation.member.id == recipient.id
            {
                ProfilePresentationContent(
                    presentation: presentation,
                    layout: .inspector,
                    openProfile: model.expandProfile,
                    userMenu: { UserContextMenu.make(for: presentation.member.user, context: .init(guildID: presentation.guildID), model: model) }
                )
            } else {
                ProgressView("Loading profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: ChatChromeMetrics.memberListWidth)
        .frame(maxHeight: .infinity)
        .clipShape(
            ConcentricRectangle(
                corners: .concentric(
                    minimum: .fixed(
                        ChatChromeMetrics.composerMinimumCornerRadius
                    )
                ),
                isUniform: true
            )
        )
        .task(id: [recipient.id, model.inspectorProfilePresentation?.member.id]) {
            if model.inspectorProfilePresentation?.member.id != recipient.id {
                model.showInspectorProfile(for: recipient)
            }
        }
    }
}

private extension SupplementaryPane {
    var motionProbeName: String {
        switch self {
        case .sideConversation: "pane"
        case .memberInspector: "members"
        case .messageSearch: "search"
        }
    }
}
