import AppKit
import SakuraCordModels
import SwiftUI

/// The structured slash-command input. It owns its text locally so typing
/// never waits on SwiftUI; the draft model decides what each edit means.
struct ApplicationCommandEditorView: NSViewRepresentable {
    let composer: ApplicationCommandComposerModel
    let draft: ApplicationCommandDraft
    let caretRequestRevision: Int
    let fieldIssue: ApplicationCommandFieldIssue?
    let roles: [GuildRole]
    let onKeyboardCommand: (ComposerAutocompleteCommand) -> Bool
    let onSubmit: () -> Void
    /// Leaves the command, continuing with the given ordinary message text.
    let onCancel: (String) -> Void
    let canReceiveAttachment: () -> Bool
    let receiveAttachment: (ComposerIncomingAttachments) -> Void
    @Binding var isFocused: Bool

    static let maximumHeight: CGFloat = 150

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.delegate = context.coordinator

        let textView = ApplicationCommandTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: ApplicationCommandEditorStyle.verticalInset)
        // Option values are sent verbatim; substitutions would change them.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.writingToolsBehavior = .none
        textView.unregisterDraggedTypes()
        textView.registerForDraggedTypes([.fileURL])
        textView.applySakuraCordTextSelectionAppearance()
        textView.setAccessibilityLabel("Command \(draft.command.displayName)")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        context.coordinator.render(in: textView, caret: composer.caretRequest)
        context.coordinator.appliedCaretRevision = caretRequestRevision
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ApplicationCommandTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        textView.applySakuraCordTextSelectionAppearance()
        guard !textView.hasMarkedText() else {
            coordinator.applyFocus(to: textView)
            return
        }
        let caret = coordinator.appliedCaretRevision != caretRequestRevision
            ? composer.caretRequest : nil
        coordinator.appliedCaretRevision = caretRequestRevision
        coordinator.render(in: textView, caret: caret)
        coordinator.applyFocus(to: textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = scrollView.documentView as? NSTextView else { return nil }
        // Ideal-size passes propose an unbounded width; only a real width
        // wraps, or the editor would report a single line.
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let used = context.coordinator.measure(
            textView.textStorage ?? NSTextStorage(), width: width ?? .greatestFiniteMagnitude
        )
        let height = ceil(
            max(ApplicationCommandEditorStyle.lineHeight, used.height) + textView.textContainerInset.height * 2
        )
        scrollView.hasVerticalScroller = height > Self.maximumHeight
        return CGSize(width: width ?? min(ceil(used.width), 600), height: min(height, Self.maximumHeight))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: ApplicationCommandEditorView
        var appliedCaretRevision = 0
        private(set) var document: ApplicationCommandEditorDocument?
        private var renderedSignature: Int?
        private var pendingNativeFocus: ApplicationCommandDraftFocus?
        private var pendingNativeLength = 0
        /// Where the caret belongs after a native edit. NSTextView only moves
        /// its selection after posting the change, so it cannot be read there.
        private var pendingNativeCaret = 0
        private var isApplying = false
        private var appliedFocus = false

        init(parent: ApplicationCommandEditorView) {
            self.parent = parent
        }

        /// SwiftUI asks for several candidate widths, so measurement uses its
        /// own layout rather than resizing the text the user sees.
        func measure(_ text: NSAttributedString, width: CGFloat) -> CGSize {
            let storage = NSTextStorage(attributedString: text)
            let layoutManager = NSLayoutManager()
            layoutManager.delegate = self
            let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
            layoutManager.ensureLayout(for: container)
            return layoutManager.usedRect(for: container).size
        }

        /// The model's draft is current even between SwiftUI updates.
        var draft: ApplicationCommandDraft { parent.composer.draft ?? parent.draft }

        /// Discord keeps each chip on one line; wrap before a chip, never inside.
        nonisolated func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldBreakLineByWordBeforeCharacterAt charIndex: Int
        ) -> Bool {
            MainActor.assumeIsolated {
                guard let document else { return true }
                return !document.fields.contains {
                    charIndex > $0.label.location && charIndex < NSMaxRange($0.value)
                }
            }
        }

        // MARK: Rendering

        /// Rebuilds styled text from the draft when it differs from what is shown.
        func render(in textView: ApplicationCommandTextView, caret: ApplicationCommandEditorCaret?) {
            let draft = parent.composer.draft ?? parent.draft
            let document = ApplicationCommandEditorDocument(draft: draft)
            var hasher = Hasher()
            hasher.combine(document.string)
            hasher.combine(draft.fields.map { $0.resolved.map(String.init(describing:)) })
            hasher.combine(draft.focus)
            hasher.combine(parent.fieldIssue?.fieldID)
            hasher.combine(parent.roles.map(\.colorHex))
            let signature = hasher.finalize()
            let previousSelection = textView.selectedRange()
            self.document = document
            textView.document = document
            textView.focus = draft.focus
            textView.issueFieldID = parent.fieldIssue?.fieldID
            textView.valueTints = ApplicationCommandEditorStyle.valueTints(for: draft, roles: parent.roles)
            textView.remainingOptionCount = draft.availableOptionalOptions.count
            if signature != renderedSignature {
                renderedSignature = signature
                isApplying = true
                textView.textStorage?.setAttributedString(
                    ApplicationCommandEditorStyle.attributedString(
                        document: document, draft: draft, roles: parent.roles
                    )
                )
                isApplying = false
                textView.invalidateIntrinsicContentSize()
                textView.needsDisplay = true
            }
            let target: NSRange
            if let caret {
                target = NSRange(location: document.location(of: caret), length: 0)
            } else if previousSelection.location == NSNotFound || NSMaxRange(previousSelection) > document.length {
                target = NSRange(location: document.location(of: document.caret(endOf: draft.focus)), length: 0)
            } else {
                target = previousSelection
            }
            if textView.selectedRange() != target {
                isApplying = true
                textView.setSelectedRange(target)
                isApplying = false
            }
            textView.updateTypingAttributes(for: draft)
            if caret != nil { textView.scrollRangeToVisible(target) }
        }

        func applyFocus(to textView: NSTextView) {
            guard parent.isFocused != appliedFocus else { return }
            appliedFocus = parent.isFocused
            if parent.isFocused {
                Task { @MainActor [weak textView] in
                    guard let textView, self.parent.isFocused else { return }
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }

        func textDidBeginEditing(_: Notification) {
            appliedFocus = true
            if !parent.isFocused { parent.isFocused = true }
        }

        func textDidEndEditing(_: Notification) {
            appliedFocus = false
            if parent.isFocused { parent.isFocused = false }
        }

        // MARK: Editing

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn range: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isApplying, let document, let textView = textView as? ApplicationCommandTextView
            else { return true }
            switch document.edit(replacing: range, with: replacementString ?? "", draft: draft) {
            case let .native(focus):
                pendingNativeFocus = focus
                pendingNativeLength = document.length
                pendingNativeCaret = range.location + (replacementString ?? "").utf16.count
                return true
            case let .replace(updated, caret):
                apply(updated, caret: caret, in: textView)
                return false
            case let .cancel(text):
                parent.onCancel(text)
                return false
            case .ignore:
                NSSound.beep()
                return false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let focus = pendingNativeFocus, let document,
                  let textView = notification.object as? ApplicationCommandTextView
            else { return }
            pendingNativeFocus = nil
            let delta = (textView.string as NSString).length - pendingNativeLength
            let original: NSRange? = switch focus {
            case let .field(id): document.span(id)?.value
            case let .gap(index): document.gaps.indices.contains(index) ? document.gaps[index] : nil
            }
            guard let original else { return }
            let range = NSRange(location: original.location, length: max(0, original.length + delta))
            guard NSMaxRange(range) <= (textView.string as NSString).length else { return }
            let text = (textView.string as NSString).substring(with: range)
            let caretOffset = textView.hasMarkedText()
                ? textView.selectedRange().location - range.location
                : pendingNativeCaret - range.location
            parent.composer.setText(text, for: focus)
            // Keep the local document in step so the next keystroke maps correctly.
            guard let updated = parent.composer.draft else { return }
            let caret: ApplicationCommandEditorCaret = switch updated.focus {
            case let .field(id) where updated.focus == focus: .field(id, offset: caretOffset)
            case let .gap(index) where updated.focus == focus: .gap(index, offset: caretOffset)
            default: ApplicationCommandEditorDocument(draft: updated).caret(endOf: updated.focus)
            }
            if !textView.hasMarkedText() {
                render(in: textView, caret: caret)
            } else {
                self.document = ApplicationCommandEditorDocument(draft: updated)
                textView.document = self.document
            }
        }

        private func apply(
            _ updated: ApplicationCommandDraft,
            caret: ApplicationCommandEditorCaret,
            in textView: ApplicationCommandTextView
        ) {
            parent.composer.applyEditorDraft(updated, caret: caret)
            appliedCaretRevision = parent.composer.caretRequestRevision
            render(in: textView, caret: caret)
        }

        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange old: NSRange,
            toCharacterRange new: NSRange
        ) -> NSRange {
            guard !isApplying, let document, new.length == 0 else { return new }
            let direction: ApplicationCommandEditorDirection =
                new.location > old.location ? .forward : (new.location < old.location ? .backward : .nearest)
            let isPointer = NSApp.currentEvent.map {
                [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains($0.type)
            } ?? false
            return NSRange(
                location: document.snap(new.location, direction: isPointer ? .nearest : direction),
                length: 0
            )
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplying, let document,
                  let textView = notification.object as? ApplicationCommandTextView
            else { return }
            let selection = textView.selectedRange()
            if let focus = document.focus(at: selection.location),
               selection.length == 0 || document.focus(at: NSMaxRange(selection)) == focus
            {
                parent.composer.setFocus(focus)
                textView.focus = focus
                textView.needsDisplay = true
            }
            if let draft = parent.composer.draft {
                textView.updateTypingAttributes(for: draft)
            }
        }

        // MARK: Keyboard

        /// Backspace at chip edges, matching Discord: from the gap after a chip
        /// it enters that chip and deletes its last character (a chosen entity
        /// as a whole); an empty optional chip is removed; at the command it
        /// turns the whole command back into ordinary text.
        func deleteBackward(in textView: ApplicationCommandTextView) -> Bool {
            guard let document, textView.selectedRange().length == 0 else { return false }
            let location = textView.selectedRange().location
            let draft = draft
            if let span = document.fields.first(where: {
                location >= $0.value.location && location <= NSMaxRange($0.value)
            }), let field = draft.field(span.id), let index = draft.index(of: span.id) {
                if span.isAtomic, location == NSMaxRange(span.value), span.value.length > 0 {
                    var updated = draft
                    updated.setText("", for: span.id)
                    apply(updated, caret: .field(span.id, offset: 0), in: textView)
                    return true
                }
                guard location == span.value.location else { return false }
                var updated = draft
                if field.isEmpty, !field.option.isRequired {
                    updated.removeField(span.id)
                }
                updated.focus = .gap(index)
                apply(updated, caret: .gap(index, offset: 0), in: textView)
                return true
            }
            guard let gap = document.gaps.firstIndex(where: { $0.location == location }) else { return false }
            guard gap > 0 else {
                parent.onCancel(draft.plainTextAfterDeletingCommand)
                return true
            }
            var updated = draft
            guard let focus = updated.deleteBackward(intoFieldBefore: gap) else { return false }
            apply(
                updated,
                caret: ApplicationCommandEditorDocument(draft: updated).caret(endOf: focus),
                in: textView
            )
            return true
        }

        /// Forward delete at a value's end steps into the following gap.
        func deleteForward(in textView: ApplicationCommandTextView) -> Bool {
            guard let document, textView.selectedRange().length == 0 else { return false }
            let location = textView.selectedRange().location
            guard let index = document.fields.firstIndex(where: { NSMaxRange($0.value) == location })
            else { return false }
            let span = document.fields[index]
            if span.isAtomic, span.value.length > 0, location == span.value.location {
                return false
            }
            moveCaret(to: .gap(index + 1, offset: 0), in: textView)
            return true
        }

        private func moveCaret(to caret: ApplicationCommandEditorCaret, in textView: ApplicationCommandTextView) {
            guard let document else { return }
            textView.setSelectedRange(NSRange(location: document.location(of: caret), length: 0))
        }

        func plainText(for range: NSRange) -> String {
            document?.plainText(in: range) ?? ""
        }

        /// Key commands can move focus in the model; adopt that caret now so
        /// the next keystroke lands in the right place.
        func keyboardCommand(_ command: ComposerAutocompleteCommand, in textView: ApplicationCommandTextView) -> Bool {
            let handled = parent.onKeyboardCommand(command)
            syncCaret(in: textView)
            return handled
        }

        func syncCaret(in textView: ApplicationCommandTextView) {
            guard parent.composer.draft != nil,
                  appliedCaretRevision != parent.composer.caretRequestRevision
            else { return }
            appliedCaretRevision = parent.composer.caretRequestRevision
            render(in: textView, caret: parent.composer.caretRequest)
        }

        func submit() {
            parent.onSubmit()
        }

        func canReceiveAttachment() -> Bool {
            parent.canReceiveAttachment()
        }

        func receiveAttachment(_ attachments: ComposerIncomingAttachments) {
            parent.receiveAttachment(attachments)
        }
    }
}

/// Typography and colours shared by the editor's text and chip drawing.
enum ApplicationCommandEditorStyle {
    static let font = NSFont.systemFont(ofSize: 15)
    static let lineHeight: CGFloat = 24
    static let verticalInset: CGFloat = 6
    static let chipPadding: CGFloat = 6
    static let labelGap: CGFloat = 10
    static let separatorKern: CGFloat = 6
    static let chipLeadingKern: CGFloat = 4

    static let partKey = NSAttributedString.Key("dev.sakuracord.command-part")

    private static var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static func baseAttributes(color: NSColor = .labelColor, font: NSFont = font) -> [NSAttributedString.Key: Any] {
        // A fixed line taller than the font leaves the extra space above the
        // glyphs; lift them so text sits centred in its chip.
        [.font: font, .foregroundColor: color, .paragraphStyle: paragraph, .baselineOffset: 3]
    }

    static func attributedString(
        document: ApplicationCommandEditorDocument,
        draft: ApplicationCommandDraft,
        roles: [GuildRole]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: document.string,
            attributes: baseAttributes()
        )
        result.addAttributes(
            [.font: NSFont.systemFont(ofSize: 15, weight: .semibold)],
            range: document.command
        )
        // The space before each gap separates chips; the space after it is
        // covered by the next chip's leading padding.
        let separators = document.gaps.map { $0.location - 1 }
        let paddings = document.fields.map { $0.label.location - 1 }
        for location in paddings where location >= 0 && location < result.length {
            result.addAttribute(.kern, value: chipLeadingKern, range: NSRange(location: location, length: 1))
        }
        for span in document.fields {
            result.addAttributes([
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
                .baselineOffset: 3.5,
                partKey: "label",
            ], range: span.label)
            if span.label.length > 0 {
                result.addAttribute(
                    .kern, value: labelGap,
                    range: NSRange(location: NSMaxRange(span.label) - 1, length: 1)
                )
            }
            guard let field = draft.field(span.id), span.value.length > 0 else { continue }
            result.addAttributes(valueAttributes(for: field, roles: roles), range: span.value)
        }
        for location in separators where location >= 0 && location < result.length {
            result.addAttribute(.kern, value: separatorKern, range: NSRange(location: location, length: 1))
        }
        return result
    }

    static func valueTints(for draft: ApplicationCommandDraft, roles: [GuildRole]) -> [String: NSColor] {
        var tints: [String: NSColor] = [:]
        for field in draft.fields {
            switch field.resolved {
            case .user?, .channel?:
                tints[field.id] = .sakuraCordAccentColor
            case let .role(id)?:
                tints[field.id] = SakuraCordAccentColor.nsColor(forRoleColorHex: roles.first { $0.id == id }?.colorHex)
            case let .mentionable(id)?:
                tints[field.id] = roles.first { $0.id.description == id }
                    .map { SakuraCordAccentColor.nsColor(forRoleColorHex: $0.colorHex) } ?? .sakuraCordAccentColor
            default:
                break
            }
        }
        return tints
    }

    static func valueAttributes(for field: ApplicationCommandDraftField, roles: [GuildRole]) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes()
        attributes[partKey] = "value"
        guard let resolved = field.resolved else { return attributes }
        switch resolved {
        case .user, .channel, .mentionable:
            attributes[.font] = NSFont.systemFont(ofSize: 15, weight: .semibold)
            attributes[.foregroundColor] = NSColor.sakuraCordAccentColor
            if case let .mentionable(id) = resolved, let role = roles.first(where: { $0.id.description == id }) {
                attributes[.foregroundColor] = SakuraCordAccentColor.nsColor(forRoleColorHex: role.colorHex)
            }
        case let .role(id):
            attributes[.font] = NSFont.systemFont(ofSize: 15, weight: .semibold)
            attributes[.foregroundColor] = SakuraCordAccentColor.nsColor(
                forRoleColorHex: roles.first { $0.id == id }?.colorHex
            )
        case .attachment:
            attributes[.font] = NSFont.systemFont(ofSize: 14, weight: .medium)
        default:
            attributes[.font] = NSFont.systemFont(ofSize: 15, weight: .medium)
        }
        return attributes
    }
}

final class ApplicationCommandTextView: NSTextView {
    weak var coordinator: ApplicationCommandEditorView.Coordinator?
    var document: ApplicationCommandEditorDocument?
    var focus: ApplicationCommandDraftFocus?
    var issueFieldID: String?
    var commandPasteboard = NSPasteboard.general
    private lazy var unfocusedTypingMonitor = ComposerUnfocusedTypingMonitor()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Take focus as soon as the editor replaces the plain composer, so a
        // key typed right after choosing a command is not lost in between.
        if let window, coordinator?.parent.isFocused == true {
            window.makeFirstResponder(self)
        }
        unfocusedTypingMonitor.synchronize(
            with: self,
            enabled: true,
            onUnfocusedReturn: { [weak self] _ in
                guard let self else { return false }
                self.coordinator?.submit()
                return true
            }
        )
    }

    func updateTypingAttributes(for draft: ApplicationCommandDraft) {
        typingAttributes = ApplicationCommandEditorStyle.baseAttributes()
            .merging([ApplicationCommandEditorStyle.partKey: "value"]) { $1 }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard !hasMarkedText(), let coordinator else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection([.shift, .command, .option, .control])
        let plain = flags.isEmpty
        let command: ComposerAutocompleteCommand? = switch event.keyCode {
        case 126 where plain: .previous
        case 125 where plain: .next
        case 48 where flags.isSubset(of: [.shift]): flags.contains(.shift) ? .previousField : .advance
        case 36, 76: flags.isSubset(of: [.shift, .command]) ? .accept : nil
        case 53 where plain: .dismiss
        default: nil
        }
        if let command {
            if coordinator.keyboardCommand(command, in: self) { return }
            switch command {
            case .accept:
                coordinator.submit()
                return
            case .advance, .previousField, .dismiss:
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func deleteBackward(_ sender: Any?) {
        if coordinator?.deleteBackward(in: self) == true { return }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        if coordinator?.deleteForward(in: self) == true { return }
        super.deleteForward(sender)
    }

    override func insertNewline(_: Any?) {
        coordinator?.submit()
    }

    override func insertTab(_: Any?) {
        _ = coordinator?.keyboardCommand(.advance, in: self)
    }

    override func insertBacktab(_: Any?) {
        _ = coordinator?.keyboardCommand(.previousField, in: self)
    }

    // MARK: Pasteboard

    override func copy(_: Any?) {
        let range = selectedRange()
        guard range.length > 0, let coordinator else { return }
        commandPasteboard.clearContents()
        commandPasteboard.setString(coordinator.plainText(for: range), forType: .string)
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        insertText("", replacementRange: selectedRange())
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        coordinator?.canReceiveAttachment() == true
            ? ComposerPasteboardAttachments.readableTypes + [.string]
            : [.string]
    }

    override func paste(_ sender: Any?) {
        if coordinator?.canReceiveAttachment() == true,
           let type = commandPasteboard.availableType(from: ComposerPasteboardAttachments.readableTypes),
           let attachments = ComposerPasteboardAttachments.attachments(from: commandPasteboard, type: type)
        {
            coordinator?.receiveAttachment(attachments)
            return
        }
        guard let value = commandPasteboard.string(forType: .string) else { return }
        insertText(value, replacementRange: selectedRange())
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard coordinator?.canReceiveAttachment() == true,
              let urls = sender.draggingPasteboard.readObjects(
                  forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
              ) as? [URL], !urls.isEmpty
        else { return false }
        coordinator?.receiveAttachment(.external(urls))
        return true
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let document, let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        func lineRects(_ range: NSRange) -> [NSRect] {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rects: [NSRect] = []
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphs,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in rects.append(rect.offsetBy(dx: origin.x, dy: origin.y)) }
            return rects
        }
        let padding = ApplicationCommandEditorStyle.chipPadding
        for span in document.fields {
            let isFocused = focus == .field(span.id)
            let isInvalid = issueFieldID == span.id
            let chips = lineRects(span.chip)
            for (index, line) in chips.enumerated() {
                var chip = line
                let leading = index == 0 ? padding : 0
                let trailing = index == chips.count - 1 ? padding + (span.value.length == 0 ? 3 : 0) : 0
                chip.origin.x -= leading
                chip.size.width += leading + trailing
                chip = chip.insetBy(dx: 0, dy: 1)
                guard chip.intersects(rect) else { continue }
                let path = NSBezierPath(roundedRect: chip, xRadius: 7, yRadius: 7)
                // Discord marks only the focused or empty chip; a filled chip
                // shows its value pill alone.
                if isFocused || span.value.length == 0 {
                    NSColor.labelColor.withAlphaComponent(isFocused ? 0.07 : 0.05).setFill()
                    path.fill()
                }
                if isInvalid || isFocused {
                    (isInvalid ? NSColor.systemRed : NSColor.sakuraCordAccentColor)
                        .withAlphaComponent(0.8).setStroke()
                    path.lineWidth = 1.25
                    path.stroke()
                }
            }
            guard span.value.length > 0 else { continue }
            let tint = valueTints[span.id]
            for line in lineRects(span.value) {
                let pill = NSRect(
                    x: line.minX - 4, y: line.minY + 3, width: line.width + 8, height: line.height - 6
                )
                guard pill.intersects(rect) else { continue }
                (tint?.withAlphaComponent(0.2) ?? NSColor.labelColor.withAlphaComponent(0.11)).setFill()
                NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            }
        }
    }

    /// Mention-style tints for chosen entities, keyed by field.
    var valueTints: [String: NSColor] = [:]
    /// Optional options not yet added, shown as Discord's trailing "+N more".
    var remainingOptionCount = 0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard remainingOptionCount > 0, let layoutManager, let textContainer, textStorage?.length ?? 0 > 0
        else { return }
        let lastGlyph = layoutManager.glyphIndexForCharacter(at: max(0, (textStorage?.length ?? 1) - 1))
        var line = layoutManager.lineFragmentUsedRect(forGlyphAt: lastGlyph, effectiveRange: nil)
        line = line.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let label = NSAttributedString(string: "+\(remainingOptionCount) more", attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        let size = label.size()
        let origin = NSPoint(x: line.maxX + 8, y: line.midY - size.height / 2 + 0.5)
        // Hidden when the line has no room rather than overlapping text.
        guard origin.x + size.width <= bounds.maxX - 4 else { return }
        label.draw(at: origin)
    }
}
