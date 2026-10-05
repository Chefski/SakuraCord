import Foundation
import SakuraCordModels

/// A caret position the command editor allows: inside a field's value or in
/// a gap between chips.
enum ApplicationCommandEditorCaret: Equatable {
    case field(String, offset: Int)
    case gap(Int, offset: Int)
}

/// How a proposed text change maps onto the draft.
enum ApplicationCommandEditorEdit: Equatable {
    /// The change stays inside one editable value or gap; let the text view apply it.
    case native(ApplicationCommandDraftFocus)
    case replace(ApplicationCommandDraft, caret: ApplicationCommandEditorCaret)
    /// The whole command was replaced; continue as an ordinary message.
    case cancel(restoringText: String)
    case ignore
}

enum ApplicationCommandEditorDirection {
    case forward, backward, nearest
}

/// The flat text the command editor shows, with the range each part occupies.
/// Layout: `/command`, then for each field ` [gap] label value`, then ` [gap]`.
/// Each gap is a caret stop between chips, like Discord's editor.
struct ApplicationCommandEditorDocument: Equatable {
    struct Span: Equatable {
        let id: String
        let label: NSRange
        let value: NSRange
        let isAtomic: Bool

        var chip: NSRange { NSUnionRange(label, value) }
    }

    let string: String
    let command: NSRange
    let fields: [Span]
    /// `gaps[i]` precedes `fields[i]`; the last gap follows every field.
    let gaps: [NSRange]

    var length: Int { (string as NSString).length }

    init(draft: ApplicationCommandDraft) {
        var text = "/\(draft.command.displayName)"
        command = NSRange(location: 0, length: text.utf16.count)
        var spans: [Span] = []
        var gaps: [NSRange] = []
        func appendGap(_ index: Int) {
            text += " "
            let start = text.utf16.count
            if index == draft.gapIndex { text += draft.gapText }
            gaps.append(NSRange(location: start, length: text.utf16.count - start))
        }
        for (index, field) in draft.fields.enumerated() {
            appendGap(index)
            text += " "
            let labelStart = text.utf16.count
            text += field.option.displayName
            let valueStart = text.utf16.count
            text += field.text
            spans.append(Span(
                id: field.id,
                label: NSRange(location: labelStart, length: valueStart - labelStart),
                value: NSRange(location: valueStart, length: text.utf16.count - valueStart),
                isAtomic: field.isAtomic
            ))
        }
        appendGap(draft.fields.count)
        fields = spans
        self.gaps = gaps
        string = text
    }

    func span(_ id: String) -> Span? {
        fields.first { $0.id == id }
    }

    // MARK: Caret mapping

    func location(of caret: ApplicationCommandEditorCaret) -> Int {
        switch caret {
        case let .field(id, offset):
            guard let span = span(id) else { return NSMaxRange(gaps[gaps.count - 1]) }
            return span.value.location + min(max(0, offset), span.value.length)
        case let .gap(index, offset):
            let gap = gaps[min(max(0, index), gaps.count - 1)]
            return gap.location + min(max(0, offset), gap.length)
        }
    }

    /// The caret at the end of a focus target's current text.
    func caret(endOf focus: ApplicationCommandDraftFocus) -> ApplicationCommandEditorCaret {
        switch focus {
        case let .field(id):
            .field(id, offset: span(id)?.value.length ?? 0)
        case let .gap(index):
            .gap(index, offset: gaps.indices.contains(index) ? gaps[index].length : 0)
        }
    }

    func focus(at location: Int) -> ApplicationCommandDraftFocus? {
        if let span = fields.first(where: { contains($0.value, location) }) {
            return .field(span.id)
        }
        return gaps.firstIndex { contains($0, location) }.map(ApplicationCommandDraftFocus.gap)
    }

    /// Moves a caret off the command name, labels and separators. Atomic
    /// values only accept a caret at either end.
    private struct CaretStop {
        let start: Int
        let end: Int
        let atomic: Bool
    }

    func snap(_ location: Int, direction: ApplicationCommandEditorDirection) -> Int {
        var stops = gaps.map { CaretStop(start: $0.location, end: NSMaxRange($0), atomic: false) }
        stops += fields.map { CaretStop(start: $0.value.location, end: NSMaxRange($0.value), atomic: $0.isAtomic) }
        stops.sort { $0.start < $1.start }
        if let stop = stops.first(where: { location >= $0.start && location <= $0.end }) {
            guard stop.atomic, location != stop.start, location != stop.end else { return location }
            return switch direction {
            case .forward: stop.end
            case .backward: stop.start
            case .nearest: location - stop.start < stop.end - location ? stop.start : stop.end
            }
        }
        switch direction {
        case .forward:
            return stops.first { $0.start >= location }?.start ?? (stops.last?.end ?? length)
        case .backward:
            return stops.last { $0.end <= location }?.end ?? (stops.first?.start ?? 0)
        case .nearest:
            return stops.flatMap { [$0.start, $0.end] }
                .min { abs($0 - location) < abs($1 - location) } ?? length
        }
    }

    /// A change wholly inside one plain value or gap is native text editing.
    private func nativeFocus(for range: NSRange) -> ApplicationCommandDraftFocus? {
        if let span = fields.first(where: {
            !$0.isAtomic && range.location >= $0.value.location && NSMaxRange(range) <= NSMaxRange($0.value)
        }) {
            return .field(span.id)
        }
        return gaps.firstIndex { range.location >= $0.location && NSMaxRange(range) <= NSMaxRange($0) }
            .map(ApplicationCommandDraftFocus.gap)
    }

    /// Applies the deleted part of a change: whole chips go, atomic values
    /// clear, and partial cuts trim text. Returns the removed field IDs too.
    private func deleting(
        _ range: NSRange, from draft: ApplicationCommandDraft
    ) -> (ApplicationCommandDraft, Set<String>) {
        var updated = draft
        var removed = Set<String>()
        for span in fields {
            guard let field = draft.field(span.id) else { continue }
            let labelCut = NSIntersectionRange(range, span.label)
            let valueCut = NSIntersectionRange(range, span.value)
            let coversLabel = span.label.length > 0 && labelCut.length == span.label.length
            if coversLabel, valueCut.length == span.value.length {
                if field.option.isRequired {
                    updated.setText("", for: span.id)
                } else {
                    updated.removeField(span.id)
                    removed.insert(span.id)
                }
            } else if span.isAtomic,
                      valueCut.length > 0 || (range.length == 0 && contains(span.value, range.location))
            {
                updated.setText("", for: span.id)
            } else if valueCut.length > 0 {
                let local = NSRange(location: valueCut.location - span.value.location, length: valueCut.length)
                updated.setText((field.text as NSString).replacingCharacters(in: local, with: ""), for: span.id)
            }
        }
        if draft.gapIndex < gaps.count {
            let gap = gaps[draft.gapIndex]
            let cut = NSIntersectionRange(range, gap)
            if cut.length > 0 {
                let local = NSRange(location: cut.location - gap.location, length: cut.length)
                updated.gapText = (draft.gapText as NSString).replacingCharacters(in: local, with: "")
            }
        }
        return (updated, removed)
    }

    // MARK: Editing

    /// Maps a text-view change onto the draft. Newlines become spaces because
    /// option values are single-line.
    func edit(
        replacing range: NSRange,
        with replacement: String,
        draft: ApplicationCommandDraft
    ) -> ApplicationCommandEditorEdit {
        let text = replacement
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let isSanitized = text != replacement
        if range.length > 0, range.location <= command.location, NSMaxRange(range) >= length {
            return .cancel(restoringText: text)
        }
        // Typing cannot edit a chosen file; deleting it is a separate gesture.
        if range.length == 0, let span = fields.first(where: { contains($0.value, range.location) }),
           draft.field(span.id)?.option.type == .attachment
        {
            return .ignore
        }

        if !isSanitized, let focus = nativeFocus(for: range) {
            return .native(focus)
        }

        let deletion = deleting(range, from: draft)
        var updated = deletion.0
        let removed = deletion.1

        // Insert at the first editable place at or after where the change began.
        let anchorLocation = snap(range.location, direction: .forward)
        if let span = fields.first(where: {
            !removed.contains($0.id) && contains($0.value, anchorLocation)
        }), let field = updated.field(span.id) {
            guard field.option.type != .attachment else {
                updated.focus = .field(span.id)
                return .replace(updated, caret: .field(span.id, offset: 0))
            }
            let offset = span.isAtomic ? 0 : min(anchorLocation - span.value.location, field.text.utf16.count)
            if !text.isEmpty {
                updated.setText(
                    (field.text as NSString).replacingCharacters(
                        in: NSRange(location: offset, length: 0), with: text
                    ),
                    for: span.id
                )
            }
            updated.focus = .field(span.id)
            return .replace(updated, caret: .field(span.id, offset: offset + text.utf16.count))
        }
        // The anchor is a gap. Removing chips shifts later gap indices down.
        let gapIndex = gaps.firstIndex { contains($0, anchorLocation) } ?? (gaps.count - 1)
        let removedBefore = fields.prefix(gapIndex).filter { removed.contains($0.id) }.count
        let target = min(gapIndex - removedBefore, updated.fields.count)
        let kept = target == updated.gapIndex ? updated.gapText : ""
        let offset = target == draft.gapIndex
            ? min(max(0, anchorLocation - gaps[gapIndex].location), kept.utf16.count) : 0
        updated.focus = .gap(target)
        updated.gapText = (kept as NSString).replacingCharacters(
            in: NSRange(location: offset, length: 0), with: text
        )
        return .replace(updated, caret: .gap(target, offset: offset + text.utf16.count))
    }

    /// Plain text for the clipboard, with chips written as `name:value`.
    func plainText(in range: NSRange) -> String {
        let source = string as NSString
        let clipped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        var output = ""
        var cursor = clipped.location
        for span in fields where NSIntersectionRange(clipped, span.label).length > 0 {
            if span.label.location > cursor {
                output += source.substring(with: NSRange(location: cursor, length: span.label.location - cursor))
            }
            let labelPart = NSIntersectionRange(clipped, span.label)
            output += source.substring(with: labelPart)
            if NSMaxRange(labelPart) == NSMaxRange(span.label) { output += ":" }
            cursor = NSMaxRange(labelPart)
        }
        if NSMaxRange(clipped) > cursor {
            output += source.substring(with: NSRange(location: cursor, length: NSMaxRange(clipped) - cursor))
        }
        // Gaps render as two separator spaces; copy them as one.
        while output.contains("  ") { output = output.replacingOccurrences(of: "  ", with: " ") }
        return output
    }

    private func contains(_ range: NSRange, _ location: Int) -> Bool {
        location >= range.location && location <= NSMaxRange(range)
    }
}
