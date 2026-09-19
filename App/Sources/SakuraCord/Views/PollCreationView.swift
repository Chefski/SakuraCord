import SakuraCordModels
import SwiftUI

struct PollCreationView: View {
    let model: AppModel
    let channelID: ChannelID
    @Environment(\.windowModalContext) private var modal
    @State private var draft = PollDraft()
    @State private var nextAnswerID = 3
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var questionIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Question").font(.headline)
                        TextField("Ask a question", text: $draft.question, axis: .vertical)
                            .lineLimit(2 ... 4)
                            .textFieldStyle(.plain).font(.body)
                            .focused($questionIsFocused)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded { questionIsFocused = true })
                            .pointerStyle(.horizontalText)
                            .modifier(PollInputSurface(isFocused: questionIsFocused) { questionIsFocused = true })
                        if draft.question.utf16.count > 260 {
                            Text("\(draft.question.utf16.count)/300")
                                .font(.caption).foregroundStyle(draft.question.utf16.count > 300 ? .red : .secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Answers").font(.headline)
                        ForEach($draft.answers) { $answer in
                            PollCreationAnswerRow(model: model, answer: $answer, canRemove: draft.answers.count > 2) {
                                draft.answers.removeAll { $0.id == answer.id }
                            }
                        }
                        if draft.answers.count < 10 {
                            HStack {
                                Spacer()
                                Button {
                                    draft.answers.append(.init(id: nextAnswerID, text: ""))
                                    nextAnswerID += 1
                                } label: {
                                    Label("Add Answer", systemImage: "plus")
                                }.buttonStyle(PollButtonStyle())
                                Spacer()
                            }.padding(.top, 4)
                        }
                        HStack {
                            Text("Allow multiple answers")
                            Spacer()
                            Toggle("Allow multiple answers", isOn: $draft.allowsMultipleAnswers).labelsHidden()
                                .toggleStyle(.switch).controlSize(.small).tint(SakuraCordAccentColor.color)
                        }.padding(.top, 10)
                    }
                    HStack {
                        Text("Duration").font(.headline)
                        Spacer()
                        PollChoiceControl(title: "Duration", selection: $draft.durationHours,
                                          options: PollDraft.durations.map { .init(id: $0, title: durationLabel($0)) })
                    }
                }.padding(2)
            }.frame(maxHeight: 540)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { modal?.dismiss() }.buttonStyle(PollButtonStyle())
                Button(isSending ? "Creating…" : "Create Poll") {
                    isSending = true
                    Task {
                        if await model.createPoll(draft, in: channelID).consumedComposer {
                            modal?.callAsFunction(allowsDisabled: true)
                        } else {
                            error = model.errorMessage ?? "Could not create the poll. Try again."
                        }
                        isSending = false
                    }
                }.buttonStyle(PollButtonStyle(prominent: true))
                    .disabled(isSending || draft.validationError != nil)
            }
        }
        .padding(22).frame(width: 480)
        .disabled(isSending)
        .windowModalSize(width: 524)
        .windowModalDismissDisabled(isSending)
    }

    private func durationLabel(_ hours: Int) -> String {
        switch hours {
        case 1: "1 hour"
        case 4, 8: "\(hours) hours"
        case 24: "24 hours"
        case 72: "3 days"
        case 168: "1 week"
        default: "2 weeks"
        }
    }
}

private struct PollCreationAnswerRow: View {
    let model: AppModel
    @Binding var answer: PollAnswer
    let canRemove: Bool
    let remove: () -> Void
    @State private var showsEmojiPicker = false
    @State private var emojiIsHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button { showsEmojiPicker.toggle() } label: {
                Group {
                    if let emoji = answer.emoji {
                        if let url = emoji.imageURL(size: 64) {
                            AnimatedRemoteImage(url: url, animates: false, contentMode: .fit, usesSwiftUIRendering: true)
                        } else { Text(emoji.name).font(.system(size: 20)) }
                    } else { Image(systemName: "face.smiling").font(.system(size: 20)).foregroundStyle(.secondary) }
                }.frame(width: 22, height: 22).allowsHitTesting(false)
                    .frame(width: 34, height: 34).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.primary.opacity(emojiIsHovered || showsEmojiPicker ? 0.14 : 0), in: Circle())
            .onModalHover { emojiIsHovered = $0 }
            .help("Choose answer emoji").accessibilityLabel("Choose answer emoji")
            .background {
                StableReactionPickerPresenter(isPresented: $showsEmojiPicker, preferredEdge: .maxX,
                                              accessibilityIdentifier: "poll-answer-emoji-picker") {
                    EmojiPickerView(model: model, useCase: .reaction(guildID: model.selectedGuildID),
                                    dismiss: { showsEmojiPicker = false }, select: { activation in
                        switch activation.selection {
                        case .native(let value): answer.emoji = EmojiReference(rawToken: value)
                        case .custom(let value): answer.emoji = EmojiReference(rawToken: value.messageToken)
                        }
                        showsEmojiPicker = false
                    })
                }
            }
            .contextMenu {
                if answer.emoji != nil { Button("Remove Emoji") { answer.emoji = nil } }
            }
            TextField("Answer", text: $answer.text, axis: .vertical)
                .textFieldStyle(.plain).font(.body).lineLimit(1 ... 3)
                .focused($isFocused)
                .padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { isFocused = true })
                .pointerStyle(.horizontalText)
            if answer.text.utf16.count > 45 {
                Text("\(answer.text.utf16.count)/55").font(.caption2)
                    .foregroundStyle(answer.text.utf16.count > 55 ? .red : .secondary)
            }
            if canRemove {
                HoverActionButton(systemImage: "xmark", help: "Remove answer", diameter: 28, action: remove)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .modifier(PollInputSurface(isFocused: isFocused) { isFocused = true })
    }
}
