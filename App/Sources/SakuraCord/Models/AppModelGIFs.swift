import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    func searchGIFs(_ query: String) {
        gifSearchTask?.cancel()
        isLoadingGIFs = true
        gifErrorMessage = nil
        let session = accountSession()
        gifSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard await session.provider.supports(.gifs),
                      isCurrentAccountSession(session)
                else {
                    throw ChatProviderError.capabilityDisabled(.gifs)
                }
                let values =
                    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? try await session.provider.trendingGIFs()
                        : try await session.provider.searchGIFs(query: query)
                guard !Task.isCancelled,
                      isCurrentAccountSession(session)
                else { return }
                gifResults = values
                isLoadingGIFs = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      isCurrentAccountSession(session)
                else { return }
                gifResults = []
                gifErrorMessage = error.localizedDescription
                isLoadingGIFs = false
            }
        }
    }

    func loadGIFPicker() {
        gifPickerLoadTask?.cancel()
        gifPickerLoadGeneration &+= 1
        let generation = gifPickerLoadGeneration
        isLoadingGIFPicker = true
        gifErrorMessage = nil
        let session = accountSession()
        gifPickerLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if isCurrentAccountSession(session),
                   gifPickerLoadGeneration == generation
                {
                    gifPickerLoadTask = nil
                    isLoadingGIFPicker = false
                }
            }
            do {
                guard await session.provider.supports(.gifs),
                      isCurrentAccountSession(session)
                else {
                    throw ChatProviderError.capabilityDisabled(.gifs)
                }
                async let landing = session.provider.gifPickerLanding()
                async let favorites = session.provider.favoriteGIFs()
                let (loadedLanding, loadedFavorites) = try await (landing, favorites)
                guard !Task.isCancelled,
                      isCurrentAccountSession(session),
                      gifPickerLoadGeneration == generation
                else { return }
                gifCategories = loadedLanding.categories
                gifTrendingPreviewURL = loadedLanding.trendingPreviewURL
                favoriteGIFs = loadedFavorites
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      isCurrentAccountSession(session),
                      gifPickerLoadGeneration == generation
                else { return }
                gifErrorMessage = error.localizedDescription
            }
        }
    }

    func setGIFFavorite(_ gif: GIFSearchResult, isFavorite: Bool) {
        guard gifFavoriteMutationURL == nil else { return }
        gifFavoriteMutationURL = gif.url
        let session = accountSession()
        Task { [weak self] in
            guard let self else { return }
            defer {
                if isCurrentAccountSession(session) {
                    gifFavoriteMutationURL = nil
                }
            }
            do {
                let favorites = try await session.provider.setGIFFavorite(
                    gif,
                    isFavorite: isFavorite
                )
                guard isCurrentAccountSession(session) else { return }
                favoriteGIFs = favorites
            } catch {
                guard isCurrentAccountSession(session) else { return }
                gifErrorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func sendGIF(_ gif: GIFSearchResult) async -> Bool {
        guard let channelID = selectedChannelID,
              selectedConversationAccess.canSend
        else { return false }
        // A picker submission owns its message value. It must never borrow or
        // restore the mutable composer across the network suspension.
        let session = accountSession()
        let replyTo = replyingTo?.id
        let mentionsRepliedUser = replyMentionsAuthor
        let replyPreview = replyingTo.map { MessageReplyPreview(message: $0) }
        guard await prepareChannelMessageSubmission(channelID: channelID, account: session) else { return false }
        return await sendChannelMessage(
            channelID: channelID,
            content: gif.url.absoluteString,
            replyTo: replyTo,
            mentionsRepliedUser: mentionsRepliedUser,
            replyPreview: replyPreview,
            attachments: [],
            clearsComposer: false
        )
    }

}
