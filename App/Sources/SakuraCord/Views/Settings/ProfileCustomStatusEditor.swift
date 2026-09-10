import SakuraCordModels
import SwiftUI

struct ProfileCustomStatusControl: View {
    let editor: ProfileEditorState
    let profile: UserProfile
    let surfaceColor: Color
    let width: CGFloat
    @State private var isPresented = false
    @State private var isHovered = false
    @State private var isClearing = false
    @State private var errorMessage: String?

    var body: some View {
        Button { isPresented = true } label: {
            ProfileStatusBubble(text: profile.customStatus ?? String(localized: "Add Status", bundle: #bundle), surfaceColor: surfaceColor, width: width)
                .allowsHitTesting(false)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.customStatus == nil ? "Add custom status" : "Edit custom status")
        .overlay(alignment: .topTrailing) {
            if isHovered, profile.customStatus != nil {
                HoverActionPill {
                    HoverActionButton(systemImage: "pencil", help: String(localized: "Edit Status", bundle: #bundle)) { isPresented = true }
                    HoverActionButton(systemImage: "trash", help: String(localized: "Clear Status", bundle: #bundle), role: .destructive) { clear() }
                }
                .offset(y: -20)
            }
        }
        .onHover { isHovered = $0 }
        .disabled(isClearing)
        .profileEditorOverlay(isPresented: $isPresented) { ProfileCustomStatusEditor(editor: editor, profile: profile) }
        .alert("Couldn’t Update Status", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func clear() {
        isClearing = true
        Task {
            defer { isClearing = false }
            do { try await editor.saveCustomStatus(nil) } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct ProfileCustomStatusEditor: View {
    let editor: ProfileEditorState
    let profile: UserProfile
    @Environment(\.profileEditorModal) private var dismiss
    @State private var text: String
    @State private var emojiID: String?
    @State private var emojiName: String?
    @State private var expiration: ProfileStatusExpiration
    @State private var expirationReferenceDate = Date.now
    @State private var showsEmojiPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isTextFocused: Bool

    init(editor: ProfileEditorState, profile: UserProfile) {
        self.editor = editor
        self.profile = profile
        let status = editor.snapshot?.customStatus
        _text = State(initialValue: status?.text ?? "")
        _emojiID = State(initialValue: status?.emojiID)
        _emojiName = State(initialValue: status?.emojiName)
        _expiration = State(initialValue: ProfileStatusExpiration.initial(for: status))
    }

    private var preview: UserProfile {
        var value = profile
        value.customStatus = draft.displayText.isEmpty ? String(localized: "Add Status", bundle: #bundle) : draft.displayText
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Set your status", bundle: #bundle).font(.title3.bold())
                Spacer()
                HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { dismiss?() }
            }
            MemberProfilePopover(member: Member(user: preview.user, roleName: "", status: preview.status), profile: preview,
                                 isLoading: false, errorMessage: nil, maximumPopoverHeight: 270,
                                 showsRoles: false, footer: EmptyView(), showsDetails: false)
                .scaleEffect(290 / 330, anchor: .top)
                .frame(maxWidth: .infinity).frame(height: 238)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                Text("Status", bundle: #bundle).font(.headline)
                HStack(alignment: .top, spacing: 8) {
                    Button { showsEmojiPicker.toggle() } label: {
                        if emojiID != nil || emojiName != nil {
                            ProfileStatusTextView(source: ProfileCustomStatus(text: "", emojiID: emojiID, emojiName: emojiName).displayText, isExpanded: false, onHoverChange: { _ in })
                                .frame(width: 24, height: 24)
                        } else { Image(systemName: "face.smiling.fill").font(.title2).frame(width: 24, height: 24) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Status emoji: \(emojiName ?? String(localized: "not set", bundle: #bundle))")
                    .profileEditorOverlay(isPresented: $showsEmojiPicker, title: "Emoji") {
                        EmojiPickerView(model: editor.model, useCase: .customStatus, dismiss: { showsEmojiPicker = false }, select: { activation in
                            switch activation.selection {
                            case let .native(value): emojiID = nil; emojiName = value
                            case let .custom(emoji):
                                guard profile.user.premiumType > 0 else {
                                    errorMessage = String(localized: "Custom status emojis require Nitro.", bundle: #bundle)
                                    return
                                }
                                emojiID = emoji.id; emojiName = emoji.name
                            }
                            showsEmojiPicker = false
                        })
                    }
                    TextField("Add Status", text: $text, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1 ... 3).focused($isTextFocused)
                        .onKeyPress(phases: .down) { press in
                            guard press.key == .return else { return .ignored }
                            if !press.modifiers.contains(.shift) { save() }
                            return .handled
                        }
                        .onChange(of: text) { _, value in
                            if value.utf16.count > 128 { while text.utf16.count > 128 { text.removeLast() } }
                        }
                    if !text.isEmpty || emojiName != nil || emojiID != nil {
                        Button("Clear", systemImage: "xmark") { text = ""; emojiID = nil; emojiName = nil }
                            .buttonStyle(.plain).labelStyle(.iconOnly)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: ConcentricRectangle(cornerRadius: 8))
                .overlay { ConcentricRectangle(cornerRadius: 8).stroke(isTextFocused ? SakuraCordAccentColor.color : .primary.opacity(0.15)) }
                if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            }
            Spacer(minLength: 0)
            HStack {
                Menu {
                    Picker("Clear after", selection: $expiration) {
                        ForEach(ProfileStatusExpiration.allCases, id: \.self) { duration in
                            Text(duration.optionLabel(at: expirationReferenceDate)).tag(duration)
                        }
                    }
                    .pickerStyle(.inline)
                    .onAppear { expirationReferenceDate = .now }
                } label: {
                    Text(expiration.selectedLabel(at: expirationReferenceDate))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Clear after, \(expiration.selectedLabel(at: expirationReferenceDate))")
                Spacer()
                Button { save() } label: {
                    if isSaving { ProgressView().controlSize(.small) } else { Text("Save", bundle: #bundle) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).profileEditorModalSize(width: 460, height: 520)
        .disabled(isSaving)
        .profileEditorDismissDisabled(isSaving)
        .onExitCommand { if !isSaving { dismiss?() } }
        .onAppear { isTextFocused = true }
    }

    private var draft: ProfileCustomStatus { ProfileCustomStatus(text: text, emojiID: emojiID, emojiName: emojiName) }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        var status = draft
        status.expiresAt = expiration.seconds.map { .now.addingTimeInterval($0) }
        Task {
            defer { isSaving = false }
            do { try await editor.saveCustomStatus(status); dismiss?(allowsDisabled: true) } catch { errorMessage = error.localizedDescription }
        }
    }
}

private enum ProfileStatusExpiration: CaseIterable {
    case day, fourHours, hour, halfHour, never

    var seconds: TimeInterval? {
        switch self {
        case .day: 86400
        case .fourHours: 14400
        case .hour: 3600
        case .halfHour: 1800
        case .never: nil
        }
    }

    private var label: String {
        switch self {
        case .day: String(localized: "24 hours", bundle: #bundle)
        case .fourHours: String(localized: "4 hours", bundle: #bundle)
        case .hour: String(localized: "1 hour", bundle: #bundle)
        case .halfHour: String(localized: "30 minutes", bundle: #bundle)
        case .never: String(localized: "Don’t clear", bundle: #bundle)
        }
    }

    func optionLabel(at now: Date) -> String {
        guard let seconds else { return label }
        let expiry = now.addingTimeInterval(seconds)
        let time = expiry.formatted(date: .omitted, time: .shortened)
        let timestamp = Calendar.current.isDate(now, inSameDayAs: expiry) ? time : String(localized: "tomorrow at \(time)", bundle: #bundle)
        return "\(label) (\(timestamp))"
    }

    func selectedLabel(at now: Date) -> String {
        guard let seconds else { return label }
        let expiry = now.addingTimeInterval(seconds)
        let time = expiry.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDate(now, inSameDayAs: expiry)
            ? String(localized: "Clear at \(time)", bundle: #bundle)
            : String(localized: "Clear tomorrow at \(time)", bundle: #bundle)
    }

    static func initial(for status: ProfileCustomStatus?) -> Self {
        guard let status else { return .day }
        guard let expiry = status.expiresAt else { return .never }
        guard Calendar.current.isDateInToday(expiry) else { return .day }
        return [Self.halfHour, .hour, .fourHours].first { expiry.timeIntervalSinceNow <= ($0.seconds ?? 0) } ?? .day
    }
}
