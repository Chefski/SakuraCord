import SakuraCordModels
import SwiftUI

/// The Threads browser for the selected text or announcement channel.
struct ThreadBrowserPopoverView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var browser = model.threadBrowser
        VStack(spacing: 0) {
            header(browser)
            Divider()
            content(browser)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: InterfaceScale.metric(440), height: InterfaceScale.metric(560))
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.threadBrowserSections)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: browser.search)
        .onExitCommand { model.dismissThreadBrowser() }
        .onChange(of: model.selectedChannelID) { model.dismissThreadBrowser() }
        .onDisappear {
            if browser.isPresented { model.dismissThreadBrowser() }
        }
    }

    private func header(_ browser: ThreadBrowserState) -> some View {
        @Bindable var browser = browser
        return VStack(spacing: InterfaceScale.metric(10)) {
            HStack {
                Label {
                    Text("Threads")
                } icon: {
                    SakuraCordSystemSymbol.swiftUIImage(named: SakuraCordSystemSymbol.thread)
                }
                .font(.interface(.headline))
                Spacer()
                if model.canCreateThreadInSelectedChannel {
                    Button("Create", systemImage: "plus", action: model.createThreadFromBrowser)
                        .help("Create Thread")
                }
            }
            TextField("Search for Thread Name", text: $browser.searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.submitThreadBrowserSearch)
                .onChange(of: browser.searchText) { _, text in
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        model.clearThreadBrowserSearch()
                    }
                }
        }
        .padding(.horizontal, InterfaceScale.metric(14))
        .padding(.vertical, InterfaceScale.metric(10))
    }

    @ViewBuilder
    private func content(_ browser: ThreadBrowserState) -> some View {
        if let search = browser.search {
            searchContent(search, browser: browser)
        } else {
            sectionsContent(browser)
        }
    }

    @ViewBuilder
    private func searchContent(_ search: ThreadBrowserSearch, browser: ThreadBrowserState) -> some View {
        if !search.hasLoaded {
            ProgressView()
        } else if let error = browser.searchErrorMessage {
            ContentUnavailableView {
                Label("Couldn't Search Threads", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again", action: model.submitThreadBrowserSearch)
            }
        } else if model.threadBrowserSearchResults.isEmpty {
            ContentUnavailableView.search(text: search.query)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    rows(model.threadBrowserSearchResults)
                }
                .padding(.vertical, InterfaceScale.metric(6))
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private func sectionsContent(_ browser: ThreadBrowserState) -> some View {
        let sections = model.threadBrowserSections
        let listing = browser.listing
        let isLoadingFirstPage = listing?.hasLoadedFirstPage != true && browser.archivedErrorMessage == nil
        if sections.isEmpty, isLoadingFirstPage {
            ProgressView()
        } else if sections.isEmpty, listing?.hasMore == false {
            ContentUnavailableView(
                "No Threads",
                systemImage: "bubble.left.and.text.bubble.right",
                description: Text("Threads started in this channel appear here.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !sections.joined.isEmpty {
                        sectionHeader(Self.count(sections.joined.count, "joined thread"))
                        rows(sections.joined)
                    }
                    if !sections.otherActive.isEmpty {
                        sectionHeader(Self.count(sections.otherActive.count, "other active thread"))
                        rows(sections.otherActive)
                    }
                    sectionHeader("Older threads")
                    rows(sections.older)
                    archivedFooter(browser, sections: sections)
                        .padding(.horizontal, InterfaceScale.metric(14))
                        .padding(.vertical, InterfaceScale.metric(8))
                }
                .padding(.vertical, InterfaceScale.metric(6))
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private static func count(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.interface(.caption).weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, InterfaceScale.metric(14))
            .padding(.top, InterfaceScale.metric(10))
            .padding(.bottom, InterfaceScale.metric(4))
            .accessibilityAddTraits(.isHeader)
    }

    private func rows(_ posts: [ForumPost]) -> some View {
        ForEach(posts) { post in
            ThreadBrowserRow(post: post) { model.openThreadFromBrowser(post) }
        }
    }

    @ViewBuilder
    private func archivedFooter(_ browser: ThreadBrowserState, sections: ThreadBrowserSections) -> some View {
        if let error = browser.archivedErrorMessage {
            HStack {
                Text(error)
                    .font(.interface(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Try Again", action: model.loadMoreArchivedThreads)
            }
        } else if browser.listing?.hasMore != false {
            // Reaching the end of the list loads the next page.
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .onAppear(perform: model.loadMoreArchivedThreads)
            // A page can add no visible rows; a new identity per offset makes
            // the footer request the next page again.
            .id(browser.listing?.nextOffset)
        } else if sections.older.isEmpty {
            Text("No older threads")
                .font(.interface(.caption))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ThreadBrowserRow: View {
    let post: ForumPost
    let open: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            HStack(spacing: InterfaceScale.metric(8)) {
                VStack(alignment: .leading, spacing: InterfaceScale.metric(2)) {
                    HStack(spacing: InterfaceScale.metric(4)) {
                        Text(post.thread.name)
                            .font(.interface(.body))
                            .lineLimit(1)
                        indicators
                    }
                    Text(subtitle)
                        .font(.interface(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isJoined {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .help("Joined")
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, InterfaceScale.metric(8))
            .padding(.vertical, InterfaceScale.metric(6))
            .background(
                isHovered ? Color.primary.opacity(0.07) : .clear,
                in: .rect(cornerRadius: InterfaceScale.metric(6))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, InterfaceScale.metric(6))
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isJoined ? "Joined" : "")
    }

    private var isJoined: Bool { post.thread.notificationSettings != nil }

    @ViewBuilder
    private var indicators: some View {
        Group {
            if post.thread.isPrivate {
                Image(systemName: "lock.shield").accessibilityLabel("Private")
            }
            if post.thread.isLocked {
                Image(systemName: "lock.fill").accessibilityLabel("Locked")
            }
            if post.thread.isArchived {
                Image(systemName: "archivebox").accessibilityLabel("Archived")
            }
        }
        .font(.interface(.caption))
        .foregroundStyle(.secondary)
    }

    private var subtitle: String {
        let count = post.thread.messageCount
        let messages = count == 1 ? "1 message" : "\(count) messages"
        let activity = post.lastActivityAt.formatted(.relative(presentation: .named))
        return "\(messages) · Last active \(activity)"
    }
}
