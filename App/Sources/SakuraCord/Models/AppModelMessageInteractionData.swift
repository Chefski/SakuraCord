import DiscordProtocol
import Foundation
import Observation
import SakuraCordModels

/// Commands as typed, read when their indicator's popover opens.
@Observable
final class MessageInteractionDataStore {
    enum Entry {
        case loading
        case loaded(MessageInteractionData)
        case failed

        var isLoading: Bool {
            if case .loading = self { true } else { false }
        }
    }

    var entries: [MessageID: Entry] = [:]

    func reset() {
        entries = [:]
    }
}

extension AppModel {
    func loadMessageInteractionData(for message: Message) {
        let store = messageInteractionData
        guard !accountTransitionIsActive else { return }
        switch store.entries[message.id] {
        case .loading, .loaded: return
        case .failed, nil: break
        }
        if store.entries.count >= 64,
           let evicted = store.entries.first(where: { !$0.value.isLoading })?.key {
            store.entries[evicted] = nil
        }
        store.entries[message.id] = .loading
        startAccountChildTask(account: accountSession()) { model, account in
            let entry: MessageInteractionDataStore.Entry
            do {
                entry = try await .loaded(
                    account.provider.messageInteractionData(channelID: message.channelID, messageID: message.id)
                )
            } catch {
                entry = .failed
            }
            guard model.isCurrentAccountSession(account), !Task.isCancelled else { return }
            model.messageInteractionData.entries[message.id] = entry
        }
    }
}
