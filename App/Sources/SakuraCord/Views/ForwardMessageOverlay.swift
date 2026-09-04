import OSLog
import SakuraCordModels
import SwiftUI

struct ForwardMessageOverlay: View {
    let model: AppModel
    let message: Message
    let animationState: WindowModalAnimationState
    let dismiss: () -> Void
    @State private var query = ""
    @State private var context = ""
    @State private var selectedDestinationIDs: [ForwardDestinationID] = []
    @State private var searchPinnedDestinationIDs: [ForwardDestinationID] = []
    @State private var searchIndex: ForwardDestinationSearchPolicy.Index?
    @State private var searchIndexRevision = 0
    @State private var displayedDestinations: [ForwardDestination] = []
    @State private var unqueriedDestinations: [ForwardDestination] = []
    @State private var destinationScrollPosition: ForwardDestinationID?
    @FocusState private var isContextFocused: Bool

    private struct SearchRequest: Hashable {
        let query: String
        let pinnedDestinationIDs: [ForwardDestinationID]
        let indexRevision: Int
    }

    private var isVisible: Bool {
        animationState.isVisible
    }

    private func rebuildSearchIndex() async {
        // Frecency settings improve ranking, but destination discovery itself
        // is entirely local. Never hold the first picker population behind the
        // authenticated enrichment request; its revision will rebuild this
        // index when it settles.
        if !model.hasLoadedDiscordEmojiSettings {
            Task { @MainActor in
                await model.loadDiscordEmojiSettings()
            }
        }
        guard !Task.isCancelled else { return }
        guard let index = await ForwardDestinationSearchIndexCache.shared.prepare(
            for: model,
            priority: .userInitiated
        ), !Task.isCancelled
        else { return }
        searchIndex = index
        searchIndexRevision &+= 1
    }

    private func refreshDisplayedDestinations() async {
        guard let searchIndex else {
            displayedDestinations = []
            return
        }
        let query = query
        let pins = searchPinnedDestinationIDs
        let indexRevision = searchIndexRevision
        let history = model.forwardDestinationHistory
        let originChannelID = message.channelID
        let searchTask = Task.detached(priority: .userInitiated) {
            searchIndex.results(
                query: query,
                recentChannelIDs: history,
                pinnedDestinationIDs: pins,
                originChannelID: originChannelID
            )
        }
        let results = await withTaskCancellationHandler {
            await searchTask.value
        } onCancel: {
            searchTask.cancel()
        }
        guard !Task.isCancelled else { return }
        guard self.query == query,
              searchPinnedDestinationIDs == pins,
              searchIndexRevision == indexRevision
        else { return }

        var validatedResults = validateContentPermissions(in: results)
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validatedResults = ForwardDestinationSelectionPolicy.mergingPinnedDestinations(
                pins,
                into: validatedResults,
                fallbacks: displayedDestinations + unqueriedDestinations
            )
            unqueriedDestinations = validatedResults
        }
        displayedDestinations = validatedResults
    }

    private func validateContentPermissions(
        in results: [ForwardDestination]
    ) -> [ForwardDestination] {
        let needsContentPermissionValidation = !message.attachments.isEmpty
            || !message.embeds.isEmpty
            || !message.stickers.isEmpty
            || message.flags.contains(.voiceMessage)
        guard needsContentPermissionValidation else {
            return results
        }
        return results.map { destination in
            var destination = destination
            let permissionChannel: Channel? = switch destination.kind {
            case .channel(let channel): channel
            case .thread(_, let parent): parent
            case .user: nil
            }
            if let permissionChannel {
                destination.unavailableReason = model.forwardUnavailableReason(
                    for: message,
                    destination: permissionChannel
                )
            }
            return destination
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(
                    WindowModalVisualStyle.menuBackgroundDimmingOpacity
                )
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                GlassEffectContainer(spacing: 0) {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        destinationList
                        Divider()
                        footer
                    }
                    .background(
                        Color(nsColor: .windowBackgroundColor),
                        in: ConcentricRectangle(
                            cornerRadius: ForwardPickerLayoutMetrics.cornerRadius,
                            style: .continuous
                        )
                    )
                    .overlay {
                        ConcentricRectangle(
                            cornerRadius: ForwardPickerLayoutMetrics.cornerRadius,
                            style: .continuous
                        )
                        .stroke(.separator, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
                    .scaleEffect(isVisible ? 1 : 0.965)
                    .frame(
                        width: min(
                            ForwardPickerLayoutMetrics.width,
                            max(
                                0,
                                geometry.size.width
                                    - ForwardPickerLayoutMetrics.outerInset * 2
                            )
                        ),
                        height: min(
                            ForwardPickerLayoutMetrics.height,
                            max(
                                0,
                                geometry.size.height
                                    - ForwardPickerLayoutMetrics.outerInset * 2
                            )
                        )
                    )
                    .padding(ForwardPickerLayoutMetrics.outerInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        // Keep a modal-level SwiftUI responder in the chain after Search gives
        // up focus. AppKit routes Escape through `cancelOperation(_:)`, while
        // SwiftUI's exit command reaches this focusable ancestor for controls
        // that install their own internal responder.
        .focusable()
        .focusEffectDisabled()
        .accessibilityAddTraits(.isModal)
        .animation(
            .easeOut(duration: WindowModalAnimationTiming.openingSeconds),
            value: isVisible
        )
        // Discord's UserSearchContextManager stays subscribed to UserStore,
        // GuildMemberStore, ChannelStore, and supplemental READY updates while
        // the modal is open. Rebuild only when those source stores advance;
        // typing changes the lightweight result task below and never rebuilds
        // the index.
        .task(id: model.forwardSearchSourceRevision) {
            await rebuildSearchIndex()
        }
        .task(id: SearchRequest(
            query: query,
            pinnedDestinationIDs: searchPinnedDestinationIDs,
            indexRevision: searchIndexRevision
        )) {
            await refreshDisplayedDestinations()
        }
        .onExitCommand(perform: dismiss)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Forward To")
                        .font(.title2.weight(.semibold))
                    Text(selectedDestinationIDs.count >= ForwardDestinationSearchPolicy.maximumSelections
                        ? "Maximum 5 places at once."
                        : "Select where you want to share this message.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HoverCloseButton(
                    help: "Close",
                    accessibilityIdentifier: "forward-close",
                    action: dismiss
                )
            }
            PickerSearchField(
                text: $query,
                placeholder: "Search",
                accessibilityIdentifier: "forward-search"
            )
        }
        .padding(24)
    }

    private var destinationList: some View {
        ScrollView {
            // Discord caps each result category at 20, so the picker has at most
            // 80 rows. Keeping that bounded list eager avoids SwiftUI's lazy
            // collection invalidation trap when accessibility scroll actions
            // race a live search-index update.
            VStack(spacing: 0) {
                ForEach(displayedDestinations) { destination in
                    ForwardDestinationRow(
                        destination: destination,
                        isSelected: selectedDestinationIDs.contains(destination.id)
                    ) {
                        toggle(destination.id)
                    }
                }
            }
            .padding(8)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $destinationScrollPosition, anchor: .top)
        .overlay {
            if searchIndex == nil {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading conversations")
            } else if displayedDestinations.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.forwardingErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            ForwardedMessagePreview(model: model, message: message)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add an optional message…", text: $context, axis: .vertical)
                    .tint(SakuraCordAccentColor.color)
                    .textFieldStyle(.plain)
                    .focused($isContextFocused)
                    .lineLimit(1 ... 3)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 40)
                    .contentShape(ConcentricRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture { isContextFocused = true }
                    .glassEffect(
                        .regular.interactive(),
                        in: ConcentricRectangle(cornerRadius: 12, style: .continuous)
                    )
                Button {
                    let destinations = selectedDestinationIDs
                    Task { await model.forward(message, to: destinations, context: context) }
                } label: {
                    Group {
                        if model.isForwardingMessages {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(selectedDestinationIDs.count > 1
                                ? "Send (\(selectedDestinationIDs.count))"
                                : "Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(minWidth: 66)
                    .frame(height: 40)
                    .contentShape(ConcentricRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .contentShape(ConcentricRectangle(cornerRadius: 12, style: .continuous))
                .glassEffect(
                    .regular.tint(SakuraCordAccentColor.color).interactive(),
                    in: ConcentricRectangle(cornerRadius: 12, style: .continuous)
                )
                .disabled(selectedDestinationIDs.isEmpty || model.isForwardingMessages)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
    }

    private func toggle(_ destinationID: ForwardDestinationID) {
        let selectedFromSearch = !query.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        let updatedPins = ForwardDestinationSelectionPolicy.searchPins(
            afterSelecting: destinationID,
            query: query,
            selectedDestinationIDs: selectedDestinationIDs,
            existing: searchPinnedDestinationIDs
        )
        if selectedFromSearch {
            displayedDestinations = ForwardDestinationSelectionPolicy
                .mergingPinnedDestinations(
                updatedPins,
                into: unqueriedDestinations,
                fallbacks: displayedDestinations
            )
            unqueriedDestinations = displayedDestinations
            searchPinnedDestinationIDs = updatedPins
            query = ""
            destinationScrollPosition = destinationID
        }
        if let index = selectedDestinationIDs.firstIndex(of: destinationID) {
            selectedDestinationIDs.remove(at: index)
            return
        }
        guard selectedDestinationIDs.count < ForwardDestinationSearchPolicy.maximumSelections else {
            NSSound.beep()
            return
        }
        selectedDestinationIDs.insert(destinationID, at: 0)
    }
}
