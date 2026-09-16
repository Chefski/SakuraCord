import AppKit

nonisolated enum KeyboardShortcutValidation: Equatable, Sendable {
    case valid
    case conflict(KeyboardShortcutAction)
    case invalid(String)
}

nonisolated enum KeyboardShortcutPolicy {
    static func isPlainEscape(
        keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, characters: String? = nil
    ) -> Bool {
        (keyCode == 53 || characters == "\u{1B}") && KeyboardShortcutModifiers(modifierFlags).isEmpty
    }

    static func markdownMarker(for chord: KeyboardShortcutChord) -> String? {
        guard chord.modifiers == .command else { return nil }
        return switch chord.key {
        case "b": "**"
        case "i": "*"
        case "u": "__"
        default: nil
        }
    }

    static func markdownMarker(for event: NSEvent, hasSelection: Bool) -> String? {
        guard let chord = KeyboardShortcutChord(event: event),
              chord.key != "u" || hasSelection else { return nil }
        return markdownMarker(for: chord)
    }

    static func validate(
        _ chord: KeyboardShortcutChord,
        for action: KeyboardShortcutAction,
        shortcuts: [KeyboardShortcutAction: KeyboardShortcutChord]
    ) -> KeyboardShortcutValidation {
        guard !chord.modifiers.isEmpty else {
            return .invalid("Include Command, Option, Control, or Shift with the key.")
        }
        if chord.modifiers == .shift, isPrintable(chord.key), chord.key != "\r" {
            return .invalid("Shift with a printable key is reserved for text entry.")
        }
        if let reason = appReservedReason(for: chord, action: action) {
            return .invalid(reason)
        }
        if let conflict = shortcuts.first(where: {
            $0.key != action && $0.value == chord
        })?.key {
            return .conflict(conflict)
        }
        return .valid
    }

    // Protect commands handled inside SakuraCord. System-wide shortcuts are
    // left to macOS and the user's current system shortcut configuration.
    private static func appReservedReason(
        for chord: KeyboardShortcutChord,
        action: KeyboardShortcutAction
    ) -> String? {
        if markdownMarker(for: chord) != nil {
            // Command-U is intentionally contextual: underline a selection, or
            // toggle members when there is no composer selection.
            if chord.key != "u" || action != .toggleMemberList {
                return "That shortcut is reserved for formatting composer text."
            }
        }
        let command = KeyboardShortcutModifiers.command
        if chord.key == "\r" || chord.key.first?.unicodeScalars.first?.value == NSEvent.SpecialKey.enter.unicodeScalar.value {
            if chord.modifiers == .command, action == .answerCall { return nil }
            return "Return combinations are reserved for composing messages and answering calls."
        }
        if chord.modifiers == command, let reason = commandReservedReason(chord, action: action) {
            return reason
        }
        if chord.modifiers == [command, .option], ["h", "m", "w"].contains(chord.key) {
            return "That shortcut is reserved for application window management."
        }
        if chord.modifiers == [command, .control], chord.key == "f" {
            return "That shortcut is reserved for toggling full screen."
        }
        if usesTextNavigationKey(chord.key),
           chord.modifiers.contains(.command) || chord.modifiers.contains(.option),
           !isDiscordNavigationShortcut(chord)
        {
            return "That combination is reserved for text navigation or selection."
        }
        return nil
    }

    private static func commandReservedReason(_ chord: KeyboardShortcutChord, action: KeyboardShortcutAction) -> String? {
        if ["q", "h", "m", "w"].contains(chord.key) {
            return "That shortcut is reserved by the macOS application menu."
        }
        if ["a", "c", "v", "x", "z"].contains(chord.key) {
            return "That shortcut is reserved for standard text editing."
        }
        if chord.key == "f", action != .searchCurrentConversation {
            return "Command–F is reserved for searching the current conversation."
        }
        if ("1" ... "9").contains(chord.key) {
            return "Command–1 through Command–9 are reserved for server navigation."
        }
        if chord.key == "," {
            return "Command–Comma is reserved for Settings."
        }
        if chord.key == "`" {
            return "Command–Grave Accent is reserved for cycling application windows."
        }
        return nil
    }

    private static func isDiscordNavigationShortcut(_ chord: KeyboardShortcutChord) -> Bool {
        let modifiers = chord.modifiers.subtracting(.shift)
        let key = chord.key.first?.unicodeScalars.first?.value
        switch key {
        case NSEvent.SpecialKey.upArrow.unicodeScalar.value, NSEvent.SpecialKey.downArrow.unicodeScalar.value:
            return modifiers == .option || modifiers == [.command, .option]
        case NSEvent.SpecialKey.leftArrow.unicodeScalar.value, NSEvent.SpecialKey.rightArrow.unicodeScalar.value:
            return chord.modifiers == .option || chord.modifiers == [.command, .option]
        default:
            return false
        }
    }

    private static func isPrintable(_ key: String) -> Bool {
        key.unicodeScalars.contains { !CharacterSet.controlCharacters.contains($0) }
            && !usesTextNavigationKey(key)
    }

    private static func usesTextNavigationKey(_ key: String) -> Bool {
        guard let value = key.first?.unicodeScalars.first?.value else { return false }
        return [
            NSEvent.SpecialKey.upArrow.unicodeScalar.value,
            NSEvent.SpecialKey.downArrow.unicodeScalar.value,
            NSEvent.SpecialKey.leftArrow.unicodeScalar.value,
            NSEvent.SpecialKey.rightArrow.unicodeScalar.value,
            NSEvent.SpecialKey.home.unicodeScalar.value,
            NSEvent.SpecialKey.end.unicodeScalar.value,
            NSEvent.SpecialKey.pageUp.unicodeScalar.value,
            NSEvent.SpecialKey.pageDown.unicodeScalar.value,
        ].contains(value)
    }
}
