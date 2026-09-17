import AppKit

extension ComposerNSTextView {
    override func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager,
              [.addTraitFontAction, .removeTraitFontAction].contains(manager.currentFontAction)
        else { return }
        let supported: NSFontTraitMask = [.boldFontMask, .italicFontMask]
        let added = manager.convertFontTraits([]).intersection(supported)
        let removed = supported.subtracting(manager.convertFontTraits(supported))
        let changed = added.union(removed)
        if changed == .boldFontMask { wrapSelectionInMarkdown("**") }
        if changed == .italicFontMask { wrapSelectionInMarkdown("*") }
    }

    override func underline(_ sender: Any?) {
        wrapSelectionInMarkdown("__")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        removeUnsupportedFormatting(from: menu)
        return menu
    }

    private func removeUnsupportedFormatting(from menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                if submenu.items.contains(where: { $0.action == #selector(NSFontManager.orderFrontFontPanel(_:)) }) {
                    // Keep AppKit's original items, targets, localization and
                    // validation. NSFontManager sends their changes back through
                    // changeFont(_:); underline already uses the responder chain.
                    for entry in submenu.items where !isSupportedFontItem(entry) {
                        submenu.removeItem(entry)
                    }
                    continue
                }
                removeUnsupportedFormatting(from: submenu)
                if submenu.items.allSatisfy(\.isSeparatorItem) { menu.removeItem(item) }
            } else if item.action == #selector(changeLayoutOrientation(_:)) {
                menu.removeItem(item)
            }
        }
    }

    private func isSupportedFontItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(underline(_:)) { return true }
        guard item.action == #selector(NSFontManager.addFontTrait(_:))
            || item.action == #selector(NSFontManager.removeFontTrait(_:))
        else { return false }
        let trait = NSFontTraitMask(rawValue: UInt(item.tag))
        return [.boldFontMask, .unboldFontMask, .italicFontMask, .unitalicFontMask].contains(trait)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(underline(_:)) {
            return isEditable && !hasMarkedText() && selectedRange().length > 0
        }
        if menuItem.action == #selector(changeLayoutOrientation(_:)) { return false }
        return super.validateMenuItem(menuItem)
    }

    // Native attribute edits must never become a second document format. Supported
    // commands above perform character replacements, then derive their appearance.
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard replacementString != nil else { return false }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        guard replacementStrings != nil else { return false }
        return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
    }

    override func changeLayoutOrientation(_ sender: Any?) {}
}
