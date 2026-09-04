import AppKit
import SakuraCordModels

nonisolated enum NativeTimelineTextRegion: Hashable {
    case beginningTitle
    case beginningDescription
    case content
    case embed(embedID: String, textIndex: Int)
    case component(layoutIndex: Int, textIndex: Int)
}

nonisolated struct NativeTimelineTextSpoilerRevealState: Equatable {
    var locationsByRegion:
        [NativeTimelineTextRegion: Set<Int>] = [:]

    var isEmpty: Bool {
        locationsByRegion.isEmpty
    }

    mutating func reveal(
        region: NativeTimelineTextRegion,
        rangeLocation: Int
    ) {
        locationsByRegion[region, default: []].insert(rangeLocation)
    }

    func locations(
        in region: NativeTimelineTextRegion
    ) -> Set<Int> {
        locationsByRegion[region] ?? []
    }
}

nonisolated struct NativeTimelineTextSpoilerRevealKey: Hashable {
    let messageID: MessageID
    let contentID: String
    let contentHash: Int
    let rangeLocation: Int
}

@MainActor
final class NativeTimelineSpoilerRevealStore {
    var revealMode: ChatSpoilerRevealMode = .click
    var revealedMedia: Set<NativeTimelineComponentRevealKey> = []
    var revealedText: Set<NativeTimelineTextSpoilerRevealKey> = []
    var observers: [UUID: (MessageID) -> Void] = [:]

    func isMediaRevealed(
        _ key: NativeTimelineComponentRevealKey
    ) -> Bool {
        revealMode == .always || revealedMedia.contains(key)
    }

    @discardableResult
    func revealMedia(
        _ key: NativeTimelineComponentRevealKey
    ) -> Bool {
        guard permitsCurrentRevealInteraction else { return false }
        let inserted = revealedMedia.insert(key).inserted
        if inserted {
            notifyObservers(messageID: key.messageID)
        }
        return inserted
    }

    func isTextRevealed(
        _ key: NativeTimelineTextSpoilerRevealKey
    ) -> Bool {
        revealMode == .always || revealedText.contains(key)
    }

    @discardableResult
    func revealText(
        _ key: NativeTimelineTextSpoilerRevealKey
    ) -> Bool {
        guard permitsCurrentRevealInteraction else { return false }
        let inserted = revealedText.insert(key).inserted
        if inserted {
            notifyObservers(messageID: key.messageID)
        }
        return inserted
    }

    func revealedTextLocations(
        messageID: MessageID,
        contentID: String,
        contentHash: Int
    ) -> Set<Int> {
        Set(
            revealedText.lazy
                .filter {
                    $0.messageID == messageID
                        && $0.contentID == contentID
                        && $0.contentHash == contentHash
                }
                .map(\.rangeLocation)
        )
    }

    func revealedTextLocations(
        messageID: MessageID,
        contentID: String,
        value: NSAttributedString
    ) -> Set<Int> {
        guard revealMode == .always else {
            return revealedTextLocations(
                messageID: messageID,
                contentID: contentID,
                contentHash: value.string.hashValue
            )
        }
        var locations: Set<Int> = []
        value.enumerateAttribute(
            .discordMarkdownSpoiler,
            in: NSRange(location: 0, length: value.length)
        ) { rawValue, range, _ in
            if (rawValue as? NSNumber)?.boolValue == true {
                locations.insert(range.location)
            }
        }
        return locations
    }

    private var permitsCurrentRevealInteraction: Bool {
        guard revealMode != .always else { return true }
        guard let event = NSApp?.currentEvent else {
            // Accessibility actions do not necessarily have a backing pointer
            // event, so they remain an equivalent way to reveal a spoiler.
            return true
        }
        return revealMode.permitsReveal(modifierFlags: event.modifierFlags)
    }

    func reset() {
        let messageIDs = Set(revealedMedia.lazy.map(\.messageID))
            .union(revealedText.lazy.map(\.messageID))
        guard !messageIDs.isEmpty else { return }
        revealedMedia.removeAll(keepingCapacity: true)
        revealedText.removeAll(keepingCapacity: true)
        for messageID in messageIDs {
            notifyObservers(messageID: messageID)
        }
    }

    func observe(
        _ observer: @escaping (MessageID) -> Void
    ) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    func notifyObservers(messageID: MessageID) {
        for observer in observers.values {
            observer(messageID)
        }
    }
}

@MainActor
enum NativeTimelineSpoilerConcealmentPolicy {
    static func isConcealed(
        messageID: MessageID,
        contentID: String,
        isSpoiler: Bool,
        store: NativeTimelineSpoilerRevealStore
    ) -> Bool {
        isSpoiler
            && !store.isMediaRevealed(
                NativeTimelineComponentRevealKey(
                    messageID: messageID,
                    componentID: contentID
                )
            )
    }

    static func hiddenContainerFrames(
        in layout: NativeTimelineComponentLayout,
        messageID: MessageID,
        store: NativeTimelineSpoilerRevealStore
    ) -> [CGRect] {
        let frames = layout.containers.compactMap { container in
            isConcealed(
                messageID: messageID,
                contentID: container.componentID,
                isSpoiler: container.isSpoiler,
                store: store
            ) ? container.frame : nil
        }
        return frames.filter { candidate in
            !frames.contains { other in
                other != candidate
                    && other.width * other.height
                        > candidate.width * candidate.height
                    && other.contains(
                        CGPoint(
                            x: candidate.midX,
                            y: candidate.midY
                        )
                    )
            }
        }
    }

    static func isInsideHiddenContainer(
        _ frame: CGRect,
        hiddenContainerFrames: [CGRect]
    ) -> Bool {
        hiddenContainerFrames.contains {
            $0.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    static func shouldLoadOrAnimate(
        messageID: MessageID,
        contentID: String,
        isSpoiler: Bool,
        store: NativeTimelineSpoilerRevealStore
    ) -> Bool {
        !isConcealed(
            messageID: messageID,
            contentID: contentID,
            isSpoiler: isSpoiler,
            store: store
        )
    }
}
