import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    /// Browsing needs View Channel and Read Message History on a text or
    /// announcement channel; that also covers the browser's search field.
    var canBrowseThreadsInSelectedChannel: Bool {
        guard let channel = selectedChannel, channel.guildID != nil,
              let permissions = selectedEffectivePermissions
        else { return false }
        return ThreadActionPolicy.canBrowseThreads(parentKind: channel.kind, permissions: permissions)
    }

    func toggleThreadBrowser() {
        if threadBrowser.isPresented { dismissThreadBrowser() } else { presentThreadBrowser() }
    }

    /// Joined and other active threads come from local state; older threads
    /// load once per connection and are then kept current by live events.
    func presentThreadBrowser() {
        guard sessionState == .workspace, canBrowseThreadsInSelectedChannel,
              let parentID = selectedChannelID
        else { return }
        threadBrowser.present(parentID: parentID)
        let generation = threadBrowser.generation
        threadBrowser.recordsTask = startAccountChildTask(account: accountSession()) { model, account in
            let active = await account.provider.activeThreads(in: parentID)
            guard !Task.isCancelled, model.threadBrowser.generation == generation else { return }
            for post in active where model.threadBrowser.records[post.id] == nil {
                model.threadBrowser.records[post.id] = post
            }
        }
        if threadBrowser.listing?.hasLoadedFirstPage != true {
            loadMoreArchivedThreads()
        }
    }

    func dismissThreadBrowser() {
        threadBrowser.dismiss()
    }

    /// Loads the next page of older threads; also retries a failed page.
    func loadMoreArchivedThreads() {
        guard threadBrowser.isPresented, !threadBrowser.isLoadingArchived,
              let parentID = threadBrowser.parentID
        else { return }
        let listing = threadBrowser.listings[parentID] ?? ThreadBrowserListing()
        guard let offset = listing.nextOffset else { return }
        threadBrowser.listings[parentID] = listing
        threadBrowser.isLoadingArchived = true
        threadBrowser.archivedErrorMessage = nil
        let generation = threadBrowser.generation
        threadBrowser.archivedTask = startAccountChildTask(account: accountSession()) { model, account in
            do {
                let page = try await account.provider.threadBrowserPage(
                    in: parentID,
                    query: ThreadBrowserQuery(scope: .archived(offset: offset))
                )
                guard !Task.isCancelled, model.threadBrowser.generation == generation else { return }
                model.threadBrowser.listings[parentID, default: ThreadBrowserListing()]
                    .append(page, requestedOffset: offset)
                // Page records are as new as the provider's; a thread they show
                // archived must leave the active sections.
                for post in page.posts where model.threadBrowser.records[post.id] != nil {
                    model.threadBrowser.records[post.id] = post
                }
                model.threadBrowser.isLoadingArchived = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, model.threadBrowser.generation == generation else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                model.threadBrowser.isLoadingArchived = false
                model.threadBrowser.archivedErrorMessage = error.localizedDescription
            }
        }
    }

    /// Runs the name search on submit, as the first-party browser does.
    func submitThreadBrowserSearch() {
        let query = threadBrowser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard threadBrowser.isPresented, let parentID = threadBrowser.parentID else { return }
        threadBrowser.searchTask?.cancel()
        threadBrowser.searchErrorMessage = nil
        guard !query.isEmpty else {
            threadBrowser.search = nil
            return
        }
        threadBrowser.search = ThreadBrowserSearch(query: query)
        let generation = threadBrowser.generation
        threadBrowser.searchTask = startAccountChildTask(account: accountSession()) { model, account in
            do {
                let page = try await account.provider.threadBrowserPage(
                    in: parentID,
                    query: ThreadBrowserQuery(scope: .search(query))
                )
                guard !Task.isCancelled, model.threadBrowser.generation == generation,
                      model.threadBrowser.search?.query == query
                else { return }
                model.threadBrowser.search?.results = page.posts
                model.threadBrowser.search?.hasLoaded = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, model.threadBrowser.generation == generation,
                      model.threadBrowser.search?.query == query
                else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                model.threadBrowser.search?.hasLoaded = true
                model.threadBrowser.searchErrorMessage = error.localizedDescription
            }
        }
    }

    func clearThreadBrowserSearch() {
        threadBrowser.searchTask?.cancel()
        threadBrowser.search = nil
        threadBrowser.searchErrorMessage = nil
    }

    /// Opens the thread in full view, as the first-party browser does.
    func openThreadFromBrowser(_ post: ForumPost) {
        dismissThreadBrowser()
        openSidebarThread(post.thread)
    }

    func createThreadFromBrowser() {
        dismissThreadBrowser()
        beginThreadCreation()
    }

    /// A fresh READY starts a new connection: older threads load again when
    /// next needed, and immediately if the browser is open.
    func reloadThreadBrowserAfterReady() {
        threadBrowser.invalidateArchivedListings()
        guard threadBrowser.isPresented else { return }
        presentThreadBrowser()
    }
}
