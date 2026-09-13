import AppKit
import SwiftUI

/// Keep the glass and its controls in one native view with a capsule-shaped hit region.
struct ProfileEditorSaveBar: NSViewRepresentable {
    let editor: ProfileEditorState
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.locale) private var locale

    func makeNSView(context: Context) -> SaveBarView { SaveBarView() }

    func updateNSView(_ view: SaveBarView, context: Context) {
        view.message.stringValue = String(localized: editor.requiresReload
            ? "Reload the saved profile before continuing." : "Careful — you have unsaved changes!", bundle: #bundle, locale: locale)
        view.error.stringValue = editor.errorMessage ?? ""
        view.resetButton.title = String(localized: editor.requiresReload ? "Discard Changes" : "Reset", bundle: #bundle, locale: locale)
        view.saveButton.title = String(localized: editor.requiresReload ? "Reload" : editor.isSaving ? "Saving…" : "Save Changes", bundle: #bundle, locale: locale)
        view.resetButton.isEnabled = isEnabled && !editor.isSaving
        view.saveButton.isEnabled = isEnabled && (editor.requiresReload ? !editor.isLoading : editor.canSave)
        view.saveButton.bezelColor = SakuraCordAccentColor.nsColor
        view.showsReminder = editor.showsUnsavedReminder
        view.reset = { editor.resetDraft() }
        view.save = {
            Task {
                if editor.requiresReload {
                    await editor.load(editor.scope, preferCached: false)
                } else {
                    await editor.save()
                }
            }
        }
        view.invalidateIntrinsicContentSize()
        view.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SaveBarView, context: Context) -> CGSize? {
        nsView.desiredSize(width: min(proposal.width ?? 640, 640))
    }

    final class SaveBarView: NSView {
        let message = NSTextField(wrappingLabelWithString: "")
        let error = NSTextField(wrappingLabelWithString: "")
        let resetButton = PillButton(title: "", target: nil, action: nil)
        let saveButton = PillButton(title: "", target: nil, action: nil)
        private let glass = PillGlassView()
        private let content = NSView()
        private let reminder = CAShapeLayer()
        var showsReminder = false
        var reset: () -> Void = {}
        var save: () -> Void = {}

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            glass.style = .regular
            glass.contentView = content
            addSubview(glass)
            addSubview(error)
            message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            error.font = message.font
            error.textColor = .systemRed
            content.addSubview(message)
            for button in [resetButton, saveButton] {
                button.bezelStyle = .glass
                button.borderShape = .capsule
                button.controlSize = .large
                button.target = self
                content.addSubview(button)
            }
            resetButton.action = #selector(resetClicked)
            saveButton.action = #selector(saveClicked)
            wantsLayer = true
            reminder.fillColor = nil
            reminder.strokeColor = NSColor.systemOrange.cgColor
            reminder.lineWidth = 2
            layer?.addSublayer(reminder)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private var resetWidth: CGFloat { max(72, resetButton.fittingSize.width) }
        private var saveWidth: CGFloat { max(116, saveButton.fittingSize.width) }

        private func textHeight(_ field: NSTextField, width: CGFloat) -> CGFloat {
            guard !field.stringValue.isEmpty else { return 0 }
            return ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(1, width), height: .greatestFiniteMagnitude)).height ?? 16)
        }

        private func pillHeight(width: CGFloat) -> CGFloat {
            max(48, textHeight(message, width: width - resetWidth - saveWidth - 48) + 20)
        }

        func desiredSize(width: CGFloat) -> CGSize {
            let errorHeight = textHeight(error, width: width - 40)
            return CGSize(width: width, height: pillHeight(width: width) + (errorHeight > 0 ? errorHeight + 8 : 0))
        }

        override func layout() {
            super.layout()
            let height = pillHeight(width: bounds.width)
            glass.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
            glass.cornerRadius = height / 2
            content.frame = glass.bounds
            saveButton.frame = NSRect(x: bounds.width - saveWidth - 8, y: (height - 32) / 2, width: saveWidth, height: 32)
            resetButton.frame = NSRect(x: saveButton.frame.minX - resetWidth - 8, y: (height - 32) / 2, width: resetWidth, height: 32)
            let messageWidth = max(1, resetButton.frame.minX - 32)
            let messageHeight = textHeight(message, width: messageWidth)
            message.frame = NSRect(x: 20, y: (height - messageHeight) / 2, width: messageWidth, height: messageHeight)
            error.isHidden = error.stringValue.isEmpty
            error.frame = NSRect(x: 20, y: height + 8, width: max(1, bounds.width - 40), height: max(0, bounds.height - height - 8))
            reminder.path = CGPath(roundedRect: glass.frame.insetBy(dx: 1, dy: 1), cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
            reminder.isHidden = !showsReminder
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard !isHidden, bounds.contains(local) else { return nil }
            // Decorations and the unused part of the surrounding horizontal strip
            // never own pointer input; only the actual pill can intercept it.
            return glass.hitTest(local)
        }

        @objc private func resetClicked() { reset() }
        @objc private func saveClicked() { save() }
    }

    final class PillGlassView: NSGlassEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).contains(local) else { return nil }
            return super.hitTest(point)
        }
    }

    final class PillButton: NSButton {
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).contains(local) else { return nil }
            return super.hitTest(point)
        }
    }
}
