import AppKit
import SakuraCordModels
import SwiftUI
import Testing
@testable import SakuraCord

@MainActor @Test("IME commits once across command values and optional-field boundaries")
func commandNativeComposition() throws {
    let model = ApplicationCommandComposerModel()
    let option = ApplicationCommandOption(id: "100/text", name: "text", type: .string, isRequired: true)
    let note = ApplicationCommandOption(id: "100/note", name: "note", type: .string)
    let app = ApplicationCommandApplication(id: "10", name: "Test")
    model.activate(ApplicationCommand(id: "100", rootCommandID: "100", applicationID: app.id, version: "1", name: "test", description: "", application: app, options: [option, note]))
    var cancelled: String?
    let parent = ApplicationCommandEditorView(composer: model, draft: try #require(model.draft), caretRequestRevision: 0,
        fieldIssue: nil, roles: [], onKeyboardCommand: { _ in false }, onSubmit: {}, onCancel: {
            cancelled = $0
            model.cancelActiveCommand()
        },
        canReceiveAttachment: { false }, receiveAttachment: { _ in }, isFocused: .constant(false))
    let coordinator = parent.makeCoordinator()
    let text = ApplicationCommandTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 80))
    text.coordinator = coordinator
    text.delegate = coordinator
    text.allowsUndo = false
    coordinator.render(in: text, caret: .field(option.id, offset: 0))
    coordinator.appliedCaretRevision = model.caretRequestRevision
    let unspecified = NSRange(location: NSNotFound, length: 0)
    text.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: unspecified)
    #expect(text.hasMarkedText())
    text.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0), replacementRange: unspecified)
    text.insertText("日本語🌸", replacementRange: unspecified)
    #expect(!text.hasMarkedText())
    #expect(model.draft?.field(option.id)?.text == "日本語🌸")
    #expect(text.string == ApplicationCommandEditorDocument(draft: try #require(model.draft)).string)
    model.setFocus(.gap(1))
    coordinator.render(in: text, caret: .gap(1, offset: 0))
    text.setMarkedText("note:", selectedRange: NSRange(location: 5, length: 0), replacementRange: unspecified)
    #expect(text.hasMarkedText())
    text.insertText("note:", replacementRange: unspecified)
    #expect(model.draft?.fields.map(\.id) == [option.id, note.id])
    #expect(text.string == ApplicationCommandEditorDocument(draft: try #require(model.draft)).string)
    #expect(model.draft?.focus == .field(note.id))
    text.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: unspecified)
    text.unmarkText()
    #expect(model.draft?.field(note.id)?.text == "かな")
    text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
    text.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: unspecified)
    text.insertText("普通のメッセージ", replacementRange: unspecified)
    #expect(cancelled == "普通のメッセージ")
    text.insertText("🌸", replacementRange: unspecified)
    text.insertText("続き", replacementRange: unspecified)
    #expect(cancelled == "普通のメッセージ🌸続き")
}
