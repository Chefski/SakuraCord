import AppKit
import QuartzCore

/// Cards one board pass adds. Card bitmaps rasterize off the main thread, so
/// new cards stay hidden until every one of them has its first bitmap; the
/// visible cards they replace stay until then, and everything swaps in one
/// frame. A board never shows a card without its content, nor a gap where
/// replaced cards were.
final class ForumBoardRevealGroup {
    enum Entrance {
        case none
        case animated(delay: CFTimeInterval)
        /// The delayed fade-in that keeps fast loads from flashing skeletons.
        case placeholder
    }

    struct Member {
        let card: ForumBoardCard
        let entrance: Entrance
    }

    fileprivate(set) var members: [Member] = []
    fileprivate var waiting = Set<ObjectIdentifier>()
    /// Replaced cards, recycled when the group reveals.
    fileprivate(set) var retiring: [ForumBoardCard] = []
    fileprivate var isFinished = false

    func add(_ card: ForumBoardCard, entrance: Entrance) {
        members.append(Member(card: card, entrance: entrance))
        if card.isRendering { waiting.insert(ObjectIdentifier(card)) }
    }

    /// Whether a card arriving in this group will cover `frame`.
    func covers(_ frame: CGRect) -> Bool {
        members.contains { waiting.contains(ObjectIdentifier($0.card)) && $0.card.frame.intersects(frame) }
    }

    func keepUntilRevealed(_ card: ForumBoardCard) {
        retiring.append(card)
    }
}

extension ForumBoardView {
    /// The longest a group waits for its bitmaps before showing the cards
    /// that are ready; the rest appear as their own bitmaps land.
    private static let revealTimeout: Duration = .milliseconds(400)

    func begin(_ group: ForumBoardRevealGroup) {
        guard !group.waiting.isEmpty else {
            reveal(group)
            return
        }
        for member in group.members {
            revealGroups[ObjectIdentifier(member.card)] = group
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.revealTimeout)
            self?.reveal(group)
        }
    }

    /// Recycles a card the current pass replaces. A hidden card that never
    /// appeared hands the cards it was replacing to `group`, so they stay on
    /// screen until something does, except where recycling it revealed the
    /// rest of its own group over them.
    func recycle(_ card: ForumBoardCard, replacedBy group: ForumBoardRevealGroup) {
        guard let previous = revealGroups[ObjectIdentifier(card)], previous !== group, !group.waiting.isEmpty else {
            recycle(card)
            return
        }
        let retirees = previous.retiring
        previous.retiring.removeAll()
        recycle(card)
        for retiree in retirees {
            if group.covers(retiree.frame), !isCoveredByShownCard(retiree.frame) {
                group.keepUntilRevealed(retiree)
            } else {
                recycle(retiree)
            }
        }
    }

    /// Shows a card once its first bitmap is on screen, or its whole group
    /// once the last of the group's bitmaps is.
    func cardDidCommit(_ card: ForumBoardCard, id: ForumBoardItem.Identifier) {
        refreshShimmer(card, id: id)
        let key = ObjectIdentifier(card)
        if let group = revealGroups[key] {
            group.waiting.remove(key)
            if group.waiting.isEmpty { reveal(group) }
        } else if card.layer.isHidden, cards[id] === card {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.layer.isHidden = false
            CATransaction.commit()
        }
    }

    /// Drops a recycled card from its group, revealing the group if it was
    /// the last card the group waited for.
    func leaveRevealGroup(_ card: ForumBoardCard) {
        let key = ObjectIdentifier(card)
        guard let group = revealGroups.removeValue(forKey: key) else { return }
        group.members.removeAll { $0.card === card }
        if group.waiting.remove(key) != nil, group.waiting.isEmpty { reveal(group) }
    }

    private func reveal(_ group: ForumBoardRevealGroup) {
        guard !group.isFinished else { return }
        group.isFinished = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for member in group.members {
            let card = member.card
            let key = ObjectIdentifier(card)
            if revealGroups[key] === group { revealGroups[key] = nil }
            // A card still without a bitmap stays hidden until its own lands.
            guard card.hasContent else { continue }
            card.layer.isHidden = false
            switch member.entrance {
            case .none:
                break
            case let .animated(delay):
                animateEntrance(card, delay: delay)
            case .placeholder:
                animatePlaceholderEntrance(card)
            }
        }
        let retiring = group.retiring
        group.retiring.removeAll()
        for card in retiring { recycle(card) }
        CATransaction.commit()
    }
}
