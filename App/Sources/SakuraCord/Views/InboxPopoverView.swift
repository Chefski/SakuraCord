import SakuraCordModels
import SwiftUI

struct InboxPopoverView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            InboxToolbar(model: model)
            Divider()
            InboxContent(model: model)
            if let error = model.inbox.errorMessage {
                Divider()
                HStack {
                    Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button("Retry", action: model.retryInboxLoad)
                }.padding(10)
            }
        }
        .frame(width: 460, height: 580)
        .sheet(item: Binding(get: { model.inbox.selectedEvent }, set: { model.inbox.selectedEvent = $0 })) { event in
            InboxEventDetailsView(event: event, model: model)
        }
        .alert("Age-Restricted Channel", isPresented: Binding(
            get: { model.inbox.ageRestrictedGuildID != nil },
            set: { if !$0 { model.cancelInboxAgeAgreement() } }
        )) {
            if model.snapshot?.currentUser.allowsAdultContent == true {
                Button("Continue", action: model.acceptInboxAgeAgreement)
            }
            Button("Cancel", role: .cancel, action: model.cancelInboxAgeAgreement)
        } message: {
            Text(model.snapshot?.currentUser.allowsAdultContent == true
                 ? "This channel contains age-restricted content. Do you wish to proceed?"
                 : "Confirm your age in Discord before opening this channel.")
        }
        .onExitCommand(perform: model.dismissInbox)
        .onDisappear { model.dismissInbox() }
    }
}

private struct InboxToolbar: View {
    let model: AppModel
    @State private var confirmsMarkAll = false

    var body: some View {
        let inbox = model.inbox
        HStack(spacing: 8) {
            Picker("Inbox", selection: Binding(get: { inbox.tab }, set: model.selectInboxTab)) {
                Text("Unread").tag(InboxTab.unread)
                Text("Mentions").tag(InboxTab.mentions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            Spacer(minLength: 0)
            if inbox.isLoading { ProgressView().controlSize(.mini) }
            HoverActionButton(systemImage: "arrow.clockwise", help: "Refresh Inbox", action: model.refreshInbox)
            if inbox.tab == .mentions {
                Menu {
                    Toggle("Include @everyone", isOn: Binding(
                        get: { inbox.query.includesEveryone },
                        set: { inbox.query.includesEveryone = $0; model.inboxMentionQueryDidChange() }
                    ))
                    Toggle("Include @role", isOn: Binding(
                        get: { inbox.query.includesRoles },
                        set: { inbox.query.includesRoles = $0; model.inboxMentionQueryDidChange() }
                    ))
                    if let guildID = model.selectedChannel?.guildID {
                        Toggle("All Servers", isOn: Binding(
                            get: { inbox.query.guildID == nil },
                            set: { inbox.query.guildID = $0 ? nil : guildID; model.inboxMentionQueryDidChange() }
                        ))
                    }
                } label: {
                    HoverActionControlLabel {
                        Image(systemName: "line.3.horizontal.decrease").font(.callout.weight(.medium))
                    }
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help("Filter Mentions")
                .accessibilityLabel("Filter Mentions")
            } else {
                if !inbox.undoGroups.isEmpty {
                    HoverActionButton(systemImage: "arrow.uturn.backward", help: "Undo Mark Read", action: model.undoInboxRead)
                        .keyboardShortcut("z", modifiers: .command)
                }
                HoverActionButton(systemImage: "envelope.open", help: "Mark All as Read") { confirmsMarkAll = true }
                    .disabled(inbox.groups.isEmpty)
                    .confirmationDialog("Mark all Inbox conversations as read?", isPresented: $confirmsMarkAll) {
                        Button("Mark All as Read", action: model.markAllInboxRead)
                    }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }
}

private struct InboxContent: View {
    let model: AppModel

    var body: some View {
        let inbox = model.inbox
        let isEmpty = inbox.tab == .mentions ? inbox.visibleMentions.isEmpty : inbox.groups.isEmpty
        if isEmpty, inbox.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            ContentUnavailableView(
                inbox.tab == .mentions ? "No Mentions" : "You're All Caught Up",
                systemImage: inbox.tab == .mentions ? "at" : "tray",
                description: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            NativeMessageTimelineView(
                model: model, conversation: .inbox(inbox.tab), beginning: nil,
                firstMessageStartsDayOverride: nil,
                hasMoreMessages: false, hasMoreLaterMessages: inbox.hasMore,
                isLoadingEarlier: false, isLoadingLater: inbox.isLoading,
                laterHistoryLoadFailed: inbox.errorMessage != nil,
                bottomContentInset: 0, unreadMessageID: nil, highlightedMessageID: nil,
                selectedMessageID: inbox.selectedMessageID,
                initialScrollTarget: .top,
                scrollRequest: inbox.scrollRequest, runsPerformanceAutoScroll: false,
                loadEarlier: {}, loadLater: model.loadMoreInbox,
                openReply: { id in
                    if let message = inbox.rows.first(where: { $0.message.replyTo == id })?.message {
                        model.navigateToInboxResult(message, messageID: id)
                    }
                },
                onScrollActivityChange: { _ in }, onScrollStateChange: { state in
                    if state.isNearLoadedBottom { model.loadMoreInbox() }
                },
                onUserScrollBegan: {}, onUserScrollEnded: { _ in }
            )
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }
}
