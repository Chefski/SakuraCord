import AppKit
import SakuraCordModels
import SwiftUI

/// A forum post's message preview in forum lists and the Inbox. It renders
/// the message's rich text, conceals hidden text spoilers like the timeline,
/// and reveals a spoiler in place when it is clicked. Every other click passes
/// through to the entry, which opens the post.
struct ForumPostPreviewText: NSViewRepresentable {
    let model: AppModel
    let message: Message
    let maximumNumberOfLines: Int
    let isEmphasized: Bool
    var textStyle: NSFont.TextStyle = .body
    var prefix: ForumPostPreviewTextView.Prefix?

    func makeNSView(context _: Context) -> ForumPostPreviewTextView {
        ForumPostPreviewTextView()
    }

    func updateNSView(_ view: ForumPostPreviewTextView, context _: Context) {
        let resolver = MessageMentionResolver(model: model, message: message)
        let prepared = RichMessageAttributedText.prepare(source: message.content)
        var mentions: [String: MentionPresentation] = [:]
        for case let .mention(mention) in prepared.tokens {
            mentions[mention.rawToken] = resolver.presentation(mention)
        }
        let fontSize = NSFont.preferredFont(forTextStyle: textStyle).pointSize
        view.configure(
            ForumPostPreviewTextView.Configuration(
                messageID: message.id,
                source: message.content,
                mentionPresentations: mentions,
                fontSize: fontSize,
                emojiSize: (fontSize * 1.375).rounded(),
                maximumNumberOfLines: maximumNumberOfLines,
                isEmphasized: isEmphasized,
                underlinesLinks: model.accessibilitySettings.underlinesLinks,
                prefix: prefix
            ),
            revealStore: model.timelineSpoilerRevealStore
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView view: ForumPostPreviewTextView,
        context _: Context
    ) -> CGSize? {
        view.measuredSize(proposedWidth: proposal.width)
    }

    static func dismantleNSView(_ view: ForumPostPreviewTextView, coordinator _: Void) {
        view.stopObservingReveals()
    }
}

final class ForumPostPreviewTextView: NSView {
    struct Prefix: Equatable {
        let value: NSAttributedString
        let accessibilityText: String
    }

    struct Configuration: Equatable {
        let messageID: MessageID
        let source: String
        let mentionPresentations: [String: MentionPresentation]
        let fontSize: CGFloat
        let emojiSize: CGFloat
        let maximumNumberOfLines: Int
        let isEmphasized: Bool
        let underlinesLinks: Bool
        let prefix: Prefix?
    }

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()
    private var configuration: Configuration?
    /// The message content without concealment. Reveal keys and
    /// accessibility use it; only the displayed copy conceals spoilers.
    private(set) var content = NSAttributedString()
    private var prefixLength = 0
    private weak var revealStore: NativeTimelineSpoilerRevealStore?
    private var revealObserverID: UUID?
    private var hiddenSpoilerRanges: [NSRange] = []
    private var hoveredSpoilerLocation: Int?
    private var hoverTrackingArea: NSTrackingArea?
    private var imageLoadTask: Task<Void, Never>?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byTruncatingTail
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    isolated deinit {
        imageLoadTask?.cancel()
    }

    func configure(
        _ configuration: Configuration,
        revealStore: NativeTimelineSpoilerRevealStore
    ) {
        if self.revealStore !== revealStore {
            stopObservingReveals()
            self.revealStore = revealStore
            revealObserverID = revealStore.observe { [weak self] messageID in
                guard let self, messageID == self.configuration?.messageID else { return }
                self.applySpoilerPresentation()
            }
        }
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        textContainer.maximumNumberOfLines = configuration.maximumNumberOfLines
        rebuildContent()
        loadMissingImages()
    }

    func stopObservingReveals() {
        if let revealObserverID {
            revealStore?.removeObserver(revealObserverID)
        }
        revealObserverID = nil
        imageLoadTask?.cancel()
        imageLoadTask = nil
    }

    func measuredSize(proposedWidth: CGFloat?) -> CGSize {
        let width = RichMessageTextMeasurement.constrainedWidth(proposedWidth)
        textContainer.containerSize = NSSize(
            width: width ?? RichMessageTextMeasurement.maximumWidth,
            height: .greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return CGSize(
            width: width ?? max(1, ceil(used.width)),
            height: max(1, ceil(used.height))
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer.containerSize = NSSize(
            width: max(1, newSize.width),
            height: .greatestFiniteMagnitude
        )
    }

    // MARK: Content

    private func rebuildContent() {
        guard let configuration else { return }
        let value = NSMutableAttributedString(
            attributedString: RichMessageAttributedText.make(
                source: configuration.source,
                emojiSize: configuration.emojiSize,
                baseFontSize: configuration.fontSize,
                mentionPresentations: configuration.mentionPresentations
            )
        )
        // Match the timeline: links underline only with the accessibility
        // setting, and a card that is not emphasized dims its other text.
        value.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: value.length)
        ) { link, range, _ in
            if link != nil {
                if configuration.underlinesLinks {
                    value.addAttribute(
                        .underlineStyle,
                        value: NativeTimelineLinkAppearance.hoverUnderlineStyle,
                        range: range
                    )
                }
            } else if !configuration.isEmphasized {
                value.addAttribute(
                    .foregroundColor,
                    value: NSColor.secondaryLabelColor,
                    range: range
                )
            }
        }
        content = value
        prefixLength = configuration.prefix?.value.length ?? 0
        applySpoilerPresentation()
    }

    private var revealedLocations: Set<Int> {
        guard let configuration, let revealStore else { return [] }
        return revealStore.revealedTextLocations(
            messageID: configuration.messageID,
            contentID: NativeTimelineTextSpoilerRevealKey.messageContentID,
            value: content
        )
    }

    private func applySpoilerPresentation() {
        hiddenSpoilerRanges = NativeTimelineTextSpoilers.hiddenRanges(
            in: content,
            revealedLocations: revealedLocations
        )
        if let hoveredSpoilerLocation,
           !hiddenSpoilerRanges.contains(where: { $0.location == hoveredSpoilerLocation })
        {
            self.hoveredSpoilerLocation = nil
        }
        let displayed = NSMutableAttributedString()
        if let prefix = configuration?.prefix {
            displayed.append(prefix.value)
        }
        let body = NSMutableAttributedString(attributedString: content)
        // Links keep their color but, like the rest of the card, open the
        // post; Text Kit would otherwise add its own link underline.
        body.removeAttribute(.link, range: NSRange(location: 0, length: body.length))
        for range in hiddenSpoilerRanges {
            Self.conceal(body, range: range)
        }
        displayed.append(body)
        textStorage.setAttributedString(displayed)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    /// Hides a spoiler's glyphs and inline images while keeping its
    /// layout, so revealing it does not reflow the preview.
    private static func conceal(_ value: NSMutableAttributedString, range: NSRange) {
        NativeTimelineSpoilerAppearance.concealText(in: value, range: range)
        value.enumerateAttribute(.attachment, in: range) { rawValue, attachmentRange, _ in
            guard let attachment = rawValue as? NSTextAttachment else { return }
            let placeholder = NSTextAttachment()
            placeholder.image = NSImage(size: attachment.bounds.size)
            placeholder.bounds = attachment.bounds
            value.addAttribute(.attachment, value: placeholder, range: attachmentRange)
        }
    }

    /// Inline images render from the shared caches. Rebuild once missing
    /// emoji and mention avatars have loaded.
    private func loadMissingImages() {
        imageLoadTask?.cancel()
        var emojiTokens = Set<String>()
        var avatarURLs = Set<URL>()
        content.enumerateAttributes(
            in: NSRange(location: 0, length: content.length)
        ) { attributes, _, _ in
            if let token = attributes[.discordEmojiToken] as? String,
               ComposerEmojiImageStore.shared.cachedImage(for: token) == nil
            {
                emojiTokens.insert(token)
            }
            if let url = (attributes[.attachment] as? MentionTextAttachment)?
                .presentation.avatarURL,
                MentionAvatarImageStore.shared.cachedImage(for: url) == nil
            {
                avatarURLs.insert(url)
            }
        }
        guard !emojiTokens.isEmpty || !avatarURLs.isEmpty else { return }
        imageLoadTask = Task { [weak self] in
            for token in emojiTokens {
                _ = await ComposerEmojiImageStore.shared.image(for: token)
            }
            for url in avatarURLs {
                _ = await MentionAvatarImageStore.shared.image(for: url)
            }
            guard !Task.isCancelled else { return }
            self?.rebuildContent()
        }
    }

    // MARK: Drawing

    func hiddenSpoilerFrames(for range: NSRange) -> [CGRect] {
        let visibleGlyphs = layoutManager.glyphRange(for: textContainer)
        let glyphs = NSIntersectionRange(
            layoutManager.glyphRange(
                forCharacterRange: NSRange(
                    location: range.location + prefixLength,
                    length: range.length
                ),
                actualCharacterRange: nil
            ),
            visibleGlyphs
        )
        guard glyphs.length > 0 else { return [] }
        var frames: [CGRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphs,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            frames.append(rect.insetBy(dx: -2, dy: -1))
        }
        return frames
    }

    func hiddenSpoilerLocation(at point: CGPoint) -> Int? {
        hiddenSpoilerRanges.first { range in
            hiddenSpoilerFrames(for: range).contains { $0.contains(point) }
        }?.location
    }

    override func draw(_: NSRect) {
        for range in hiddenSpoilerRanges {
            NativeTimelineSpoilerAppearance.textBackgroundColor(
                isHovered: hoveredSpoilerLocation == range.location
            ).setFill()
            for frame in hiddenSpoilerFrames(for: range) {
                NSBezierPath(
                    roundedRect: frame,
                    xRadius: NativeTimelineSpoilerAppearance.textCornerRadius,
                    yRadius: NativeTimelineSpoilerAppearance.textCornerRadius
                ).fill()
            }
        }
        let glyphs = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }

    // MARK: Pointer

    /// Only hidden spoilers take clicks; the rest of the preview belongs to
    /// the card, which opens the post.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return hiddenSpoilerLocation(at: local) == nil ? nil : self
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let location = hiddenSpoilerLocation(
            at: convert(event.locationInWindow, from: nil)
        ) else {
            super.mouseDown(with: event)
            return
        }
        revealSpoiler(at: location)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        setHoveredSpoiler(hiddenSpoilerLocation(at: convert(event.locationInWindow, from: nil)))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredSpoiler(nil)
        super.mouseExited(with: event)
    }

    override func resetCursorRects() {
        for range in hiddenSpoilerRanges {
            for frame in hiddenSpoilerFrames(for: range) {
                addCursorRect(frame, cursor: .pointingHand)
            }
        }
    }

    private func setHoveredSpoiler(_ location: Int?) {
        guard hoveredSpoilerLocation != location else { return }
        hoveredSpoilerLocation = location
        needsDisplay = true
    }

    func revealSpoiler(at location: Int) {
        guard let configuration, let revealStore else { return }
        revealStore.revealText(NativeTimelineTextSpoilerRevealKey(
            messageID: configuration.messageID,
            contentID: NativeTimelineTextSpoilerRevealKey.messageContentID,
            contentHash: content.string.hashValue,
            rangeLocation: location
        ))
    }

    // MARK: Accessibility

    override func accessibilityValue() -> Any? {
        (configuration?.prefix?.accessibilityText ?? "")
            + TimelineTextAccessibility.text(
                content,
                revealedLocations: revealedLocations
            )
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let location = hiddenSpoilerRanges.first?.location else { return nil }
        return [
            NSAccessibilityCustomAction(name: "Reveal spoiler") { [weak self] in
                self?.revealSpoiler(at: location)
                return true
            },
        ]
    }
}
