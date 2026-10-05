import SakuraCordModels
import SwiftUI
import UniformTypeIdentifiers

/// A form an application returned for an interaction. Cancelling is local;
/// submitting sends one interaction with the entered values.
struct InteractionModalView: View {
    let model: AppModel
    let form: InteractionModalFormState
    @Environment(\.windowModalContext) private var dismiss
    @Environment(\.windowModalAvailableSize) private var availableSize
    @FocusState private var focusedField: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(form.modal.nodes) { node in
                            nodeView(node)
                        }
                        privacyNotice
                        if !form.isSubmittable {
                            Label(
                                "This form uses a field SakuraCord can’t show yet, so it can’t be submitted here.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.callout)
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .frame(maxHeight: min(600, max(200, availableSize.height - 180)))
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: form.focusRequest) { _, request in
                    guard let request else { return }
                    withAnimation(.snappy) { proxy.scrollTo(request, anchor: .center) }
                    focusedField = request
                    form.consumeFocusRequest()
                }
            }
            if let error = form.formError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
            Divider()
            HStack {
                ModalGlassButton(symbol: "xmark", label: "Cancel") { dismiss?(allowsDisabled: true) }
                Spacer(minLength: 16)
                if form.isSubmitting {
                    ProgressView().controlSize(.small).padding(.trailing, 6)
                }
                ModalGlassButton(symbol: "paperplane.fill", label: "Submit", primary: true, action: submit)
                    .disabled(form.isSubmitting || !form.isSubmittable)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        .frame(width: min(500, availableSize.width))
        .task {
            await Task.yield()
            focusedField = form.controls.first { control in
                if case .textInput = control.kind { return true }
                return false
            }?.customID
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(form.modal.title)
    }

    private var header: some View {
        HStack(spacing: 12) {
            CommandApplicationIcon(application: form.modal.application, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(form.modal.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                Text(form.modal.application.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var privacyNotice: some View {
        Label(
            "This form will be submitted to \(form.modal.application.name). Don’t share passwords or other sensitive information.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func submit() {
        model.submitInteractionModal(form)
    }

    // MARK: Nodes

    private func nodeView(_ node: ModalNode) -> AnyView {
        switch node {
        case let .actionRow(_, children):
            return AnyView(VStack(alignment: .leading, spacing: 14) {
                ForEach(children) { nodeView($0) }
            })
        case let .label(_, label, description, child):
            if case let .control(control) = child, case .checkbox = control.kind {
                return AnyView(InteractionModalCheckboxRow(form: form, control: control, label: label, description: description))
            }
            return AnyView(InteractionModalFieldGroup(
                label: label,
                description: description,
                isRequired: child.controls.contains(where: \.isRequired),
                error: child.controls.first.flatMap { form.errors[$0.customID] }
            ) {
                nodeView(child)
            }
            .id(child.controls.first?.customID ?? node.id))
        case let .textDisplay(_, content):
            return AnyView(
                Text(Self.markdown(content))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        case let .control(control):
            if let label = control.label {
                // Legacy rows carry the label on the text input itself.
                return AnyView(InteractionModalFieldGroup(
                    label: label, description: nil, isRequired: control.isRequired,
                    error: form.errors[control.customID]
                ) {
                    controlView(control)
                }
                .id(control.customID))
            }
            return controlView(control)
        case let .unsupported(_, type):
            return AnyView(
                Label("Unsupported form field (type \(type))", systemImage: "questionmark.square.dashed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            )
        }
    }

    private func controlView(_ control: ModalControl) -> AnyView {
        switch control.kind {
        case let .textInput(style, placeholder, _, maximum, _):
            AnyView(InteractionModalTextField(
                form: form, control: control, style: style, placeholder: placeholder,
                maximum: maximum, focus: $focusedField, submit: submit
            ))
        case let .select(kind, placeholder, options, minimum, maximum, channelTypes, _):
            if kind == .string {
                AnyView(InteractionModalStringSelect(
                    form: form, control: control, placeholder: placeholder, options: options,
                    minimum: minimum, maximum: maximum
                ))
            } else {
                AnyView(InteractionModalEntitySelect(
                    model: model, form: form, control: control, kind: kind,
                    placeholder: placeholder, maximum: maximum, channelTypes: channelTypes
                ))
            }
        case let .radioGroup(options):
            AnyView(InteractionModalRadioGroup(form: form, control: control, options: options))
        case let .checkboxGroup(options, _, maximum):
            AnyView(InteractionModalCheckboxGroup(form: form, control: control, options: options, maximum: maximum))
        case .checkbox:
            AnyView(InteractionModalCheckboxRow(form: form, control: control, label: control.label ?? "", description: nil))
        case let .fileUpload(_, maximum, fileTypes):
            AnyView(InteractionModalFileUpload(
                model: model, form: form, control: control, maximum: maximum, fileTypes: fileTypes
            ))
        }
    }

    static func markdown(_ content: String) -> AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
    }
}

private struct InteractionModalFieldGroup<Content: View>: View {
    let label: String
    let description: String?
    let isRequired: Bool
    let error: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 13, weight: .semibold))
                if isRequired {
                    Text("*").font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
                        .accessibilityLabel("required")
                }
            }
            if let description, !description.isEmpty {
                Text(InteractionModalView.markdown(description))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content()
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared input surface: a soft rounded field like the rest of SakuraCord's forms.
private struct InteractionModalFieldBackground: ViewModifier {
    var isFocused = false
    var hasError = false
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(.quaternary.opacity(isFocused ? 0.8 : 0.5), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        hasError ? Color.red.opacity(0.8)
                            : (isFocused ? SakuraCordAccentColor.color.opacity(0.7) : .clear),
                        lineWidth: 1.5
                    )
            }
    }
}

private struct InteractionModalTextField: View {
    let form: InteractionModalFormState
    let control: ModalControl
    let style: ModalTextInputStyle
    let placeholder: String?
    let maximum: Int?
    var focus: FocusState<String?>.Binding
    let submit: () -> Void

    var body: some View {
        let binding = Binding(get: { form.text(for: control) }, set: { form.setText($0, for: control) })
        let count = form.text(for: control).unicodeScalars.count
        VStack(alignment: .trailing, spacing: 3) {
            Group {
                if style == .paragraph {
                    TextField(placeholder ?? "", text: binding, axis: .vertical)
                        .lineLimit(3 ... 10)
                } else {
                    TextField(placeholder ?? "", text: binding)
                        .onSubmit(submit)
                }
            }
            .textFieldStyle(.plain)
            .tint(SakuraCordAccentColor.color)
            .focused(focus, equals: control.customID)
            .disabled(control.isDisabled)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .modifier(InteractionModalFieldBackground(
                isFocused: focus.wrappedValue == control.customID,
                hasError: form.errors[control.customID] != nil
            ))
            if let maximum, count > maximum * 3 / 4 || style == .paragraph {
                Text("\(count)/\(maximum)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(count >= maximum ? .orange : .secondary)
            }
        }
    }
}

private struct InteractionModalStringSelect: View {
    let form: InteractionModalFormState
    let control: ModalControl
    let placeholder: String?
    let options: [ComponentSelectOption]
    let minimum: Int
    let maximum: Int
    @State private var isPresented = false

    var body: some View {
        let selected = form.selectedValues(for: control)
        // The summary follows option order; the request keeps selection order.
        let summary = options.filter { selected.contains($0.value) }
        // Same field as the entity selects: chips for chosen values and
        // Discord's down chevron.
        Button { isPresented.toggle() } label: {
            HStack(spacing: 6) {
                if summary.isEmpty {
                    Text(placeholder ?? (maximum > 1 ? "Make selections" : "Make a selection"))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else {
                    FlowLayout(spacing: 5) {
                        ForEach(summary) { option in
                            InteractionModalEntityChip(option: option) {
                                form.setSelection(selected.filter { $0 != option.value }, for: control)
                            }
                        }
                    }
                }
                Spacer(minLength: 6)
                InteractionModalSelectChevron(isOpen: isPresented)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(InteractionModalFieldBackground(
                isFocused: isPresented, hasError: form.errors[control.customID] != nil
            ))
        }
        .buttonStyle(.plain)
        .disabled(control.isDisabled)
        .escapeDismissiblePopover(isPresented: $isPresented, arrowEdge: .bottom) {
            InteractionModalOptionList(
                options: options,
                selected: selected,
                maximum: maximum,
                toggle: { option in
                    var values = form.selectedValues(for: control)
                    if let index = values.firstIndex(of: option.value) {
                        values.remove(at: index)
                    } else if maximum == 1 {
                        values = [option.value]
                    } else if values.count < maximum {
                        values.append(option.value)
                    }
                    form.setSelection(values, for: control)
                    if maximum == 1 { isPresented = false }
                }
            )
        }
    }
}

private struct InteractionModalOptionList: View {
    let options: [ComponentSelectOption]
    let selected: [String]
    let maximum: Int
    let toggle: (ComponentSelectOption) -> Void
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if options.count > 8 {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(6)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(filtered) { option in
                        let isSelected = selected.contains(option.value)
                        let isAvailable = isSelected || maximum == 1 || selected.count < maximum
                        Button { toggle(option) } label: {
                            HStack(spacing: 9) {
                                if let emoji = option.emoji {
                                    InteractionModalEmoji(emoji: emoji)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.label).foregroundStyle(.primary)
                                    if let description = option.description {
                                        Text(description).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? AnyShapeStyle(SakuraCordAccentColor.color) : AnyShapeStyle(.tertiary))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PopoverRowButtonStyle())
                        .disabled(!isAvailable)
                        .opacity(isAvailable ? 1 : 0.45)
                    }
                }
                .padding(5)
            }
            .frame(maxHeight: 300)
            if maximum > 1 {
                Text("\(selected.count) of up to \(maximum) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var filtered: [ComponentSelectOption] {
        guard !query.isEmpty else { return options }
        return options.filter {
            $0.label.localizedCaseInsensitiveContains(query)
                || $0.description?.localizedCaseInsensitiveContains(query) == true
        }
    }
}

private struct InteractionModalEmoji: View {
    let emoji: EmojiReference

    var body: some View {
        if let url = emoji.imageURL(size: 48) {
            AnimatedRemoteImage(url: url).frame(width: 20, height: 20)
        } else {
            Text(emoji.name).font(.system(size: 17))
        }
    }
}

private struct InteractionModalEntitySelect: View {
    let model: AppModel
    let form: InteractionModalFormState
    let control: ModalControl
    let kind: ComponentSelectKind
    let placeholder: String?
    let maximum: Int
    let channelTypes: [Int]
    @State private var isPresented = false

    var body: some View {
        let selection = form.entitySelection(for: control)
        HStack(spacing: 6) {
            if selection.isEmpty {
                Text(placeholder ?? defaultPlaceholder).foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(selection) { option in
                        InteractionModalEntityChip(option: option) {
                            form.setEntitySelection(selection.filter { $0.value != option.value }, for: control)
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            InteractionModalSelectChevron(isOpen: isPresented)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !control.isDisabled { isPresented = true } }
        .modifier(InteractionModalFieldBackground(
            isFocused: isPresented, hasError: form.errors[control.customID] != nil
        ))
        .escapeDismissiblePopover(isPresented: $isPresented, arrowEdge: .bottom) {
            InteractionModalEntityPicker(
                model: model,
                modal: form.modal,
                kind: kind,
                channelTypes: channelTypes,
                maximum: maximum,
                selection: form.entitySelection(for: control),
                change: { options in
                    form.setEntitySelection(options, for: control)
                    if maximum == 1, !options.isEmpty { isPresented = false }
                }
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var defaultPlaceholder: String {
        switch kind {
        case .user: maximum > 1 ? "Choose members" : "Choose a member"
        case .role: maximum > 1 ? "Choose roles" : "Choose a role"
        case .mentionable: "Choose members or roles"
        case .channel: maximum > 1 ? "Choose channels" : "Choose a channel"
        case .string: "Make a selection"
        }
    }
}

private struct InteractionModalEntityChip: View {
    let option: ComponentSelectOption
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            switch option.entityKind {
            case .user:
                AvatarView(name: option.label, url: option.imageURL, size: 18)
            case .role:
                RoleColorIndicator(colorHex: option.colorHex, size: 10)
            case .channel:
                Image(systemName: "number").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            case nil:
                if let emoji = option.emoji { InteractionModalEmoji(emoji: emoji) }
            }
            Text(option.label)
                .font(.callout.weight(.medium))
                .foregroundStyle(
                    option.entityKind == .role
                        ? SakuraCordAccentColor.color(forRoleColorHex: option.colorHex) : .primary
                )
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove \(option.label)")
        }
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

/// Searchable entity choices: cached members, roles and channels first, then
/// a server member search for anything not loaded.
private struct InteractionModalEntityPicker: View {
    let model: AppModel
    let modal: InteractionModal
    let kind: ComponentSelectKind
    let channelTypes: [Int]
    let maximum: Int
    let selection: [ComponentSelectOption]
    let change: ([ComponentSelectOption]) -> Void
    @State private var query = ""
    @State private var results: [ComponentSelectOption] = []
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(6)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(results) { option in
                        let isSelected = selection.contains { $0.value == option.value }
                        let isAvailable = isSelected || maximum == 1 || selection.count < maximum
                        Button { toggle(option) } label: {
                            HStack(spacing: 9) {
                                InteractionModalEntityIcon(option: option)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.label)
                                        .foregroundStyle(
                                            option.entityKind == .role
                                                ? SakuraCordAccentColor.color(forRoleColorHex: option.colorHex) : .primary
                                        )
                                    if let description = option.description {
                                        Text(description).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? AnyShapeStyle(SakuraCordAccentColor.color) : AnyShapeStyle(.tertiary))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PopoverRowButtonStyle())
                        .disabled(!isAvailable)
                        .opacity(isAvailable ? 1 : 0.45)
                    }
                    if results.isEmpty {
                        Text(isSearching ? "Searching…" : "No matches")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                .padding(5)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            results = local(query: "")
            searchFocused = true
        }
        .task(id: query) {
            results = local(query: query)
            guard kind != .channel, !query.isEmpty, model.supportsCapability(.remoteComponentChoices) else { return }
            isSearching = true
            defer { isSearching = false }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  let remote = try? await model.componentChoices(
                      kind: kind, query: query, guildID: modal.guildID, channelID: modal.channelID
                  ),
                  !Task.isCancelled
            else { return }
            var seen = Set(results.map(\.value))
            results += remote.filter { seen.insert($0.value).inserted }
        }
    }

    private func local(query: String) -> [ComponentSelectOption] {
        let cached = model.cachedComponentChoices(
            kind: kind, guildID: modal.guildID, channelTypes: channelTypes, limit: 200
        )
        let filtered = query.isEmpty ? cached : cached.filter {
            $0.label.localizedCaseInsensitiveContains(query)
                || $0.description?.localizedCaseInsensitiveContains(query) == true
        }
        return Array(filtered.prefix(50))
    }

    private func toggle(_ option: ComponentSelectOption) {
        var updated = selection
        if let index = updated.firstIndex(where: { $0.value == option.value }) {
            updated.remove(at: index)
        } else if maximum == 1 {
            updated = [option]
        } else if updated.count < maximum {
            updated.append(option)
        }
        change(updated)
    }
}

private struct InteractionModalEntityIcon: View {
    let option: ComponentSelectOption

    var body: some View {
        Group {
            switch option.entityKind {
            case .user:
                AvatarView(name: option.label, url: option.imageURL, size: 26)
            case .role:
                if let url = option.imageURL {
                    AnimatedRemoteImage(url: url)
                } else {
                    RoleColorIndicator(colorHex: option.colorHex, size: 13)
                }
            case .channel, nil:
                Image(systemName: option.channelKind.map {
                    ChannelIconPresentation.systemImage(for: $0, isHidden: false)
                } ?? "number")
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 26, height: 26)
    }
}

private struct InteractionModalRadioGroup: View {
    let form: InteractionModalFormState
    let control: ModalControl
    let options: [ComponentSelectOption]

    var body: some View {
        let selected = form.radioValue(for: control)
        VStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = selected == option.value
                Button { form.setRadio(option.value, for: control) } label: {
                    InteractionModalChoiceRow(
                        option: option,
                        symbol: isSelected ? "largecircle.fill.circle" : "circle",
                        isSelected: isSelected
                    )
                }
                .buttonStyle(.plain)
                .disabled(control.isDisabled)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

private struct InteractionModalCheckboxGroup: View {
    let form: InteractionModalFormState
    let control: ModalControl
    let options: [ComponentSelectOption]
    let maximum: Int

    var body: some View {
        let selected = form.selectedValues(for: control)
        VStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = selected.contains(option.value)
                // Discord disables unchecked choices once the maximum is reached.
                let isAvailable = isSelected || selected.count < maximum
                Button { form.toggleCheckboxGroupValue(option.value, for: control) } label: {
                    InteractionModalChoiceRow(
                        option: option,
                        symbol: isSelected ? "checkmark.square.fill" : "square",
                        isSelected: isSelected
                    )
                }
                .buttonStyle(.plain)
                .disabled(control.isDisabled || !isAvailable)
                .opacity(isAvailable ? 1 : 0.45)
            }
        }
    }
}

private struct InteractionModalChoiceRow: View {
    let option: ComponentSelectOption
    let symbol: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? AnyShapeStyle(SakuraCordAccentColor.color) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if let emoji = option.emoji { InteractionModalEmoji(emoji: emoji) }
                    Text(option.label).foregroundStyle(.primary)
                }
                if let description = option.description {
                    Text(description).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(InteractionModalFieldBackground(isFocused: isSelected))
    }
}

private struct InteractionModalCheckboxRow: View {
    let form: InteractionModalFormState
    let control: ModalControl
    let label: String
    let description: String?

    var body: some View {
        let isChecked = form.isChecked(control)
        // Same row as checkbox-group choices so every modal control shares one shape.
        Button { form.setChecked(!isChecked, for: control) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isChecked ? AnyShapeStyle(SakuraCordAccentColor.color) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).foregroundStyle(.primary)
                    if let description, !description.isEmpty {
                        Text(InteractionModalView.markdown(description)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(InteractionModalFieldBackground(isFocused: isChecked))
        }
        .buttonStyle(.plain)
        .disabled(control.isDisabled)
        .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : .isButton)
        .id(control.customID)
    }
}

private struct InteractionModalFileUpload: View {
    let model: AppModel
    let form: InteractionModalFormState
    let control: ModalControl
    let maximum: Int
    let fileTypes: [String]
    @State private var isImporterPresented = false
    @State private var isDropTarget = false

    var body: some View {
        let files = form.files(for: control)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(files) { file in
                HStack(spacing: 9) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                        .resizable().scaledToFit().frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name).lineLimit(1).truncationMode(.middle)
                        if let size = file.byteCount {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6)
                    HoverActionButton(systemImage: "xmark", help: "Remove \(file.name)", diameter: 26) {
                        form.removeFile(file, from: control)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .modifier(InteractionModalFieldBackground())
            }
            if files.count < maximum {
                Button { isImporterPresented = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.doc").font(.title3)
                        Text("Drop files here or click to browse").font(.callout)
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .contentShape(Rectangle())
                    .background(
                        .quaternary.opacity(isDropTarget ? 0.9 : 0.35),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                form.errors[control.customID] != nil ? Color.red.opacity(0.8) : Color.secondary.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(control.isDisabled)
                .dropDestination(for: URL.self) { urls, _ in
                    add(urls)
                    return true
                } isTargeted: { isDropTarget = $0 }
            } else {
                Label("File upload limit reached. Remove some files to upload new ones.", systemImage: "tray.full")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: InteractionModalFormState.contentTypes(for: fileTypes),
            allowsMultipleSelection: maximum - files.count > 1
        ) { result in
            guard case let .success(urls) = result else { return }
            add(urls)
        }
    }

    private var hint: String {
        let limit = maximum == 1 ? "One file" : "Up to \(maximum) files"
        guard let types = InteractionModalFormState.fileTypeDescription(fileTypes) else { return limit }
        return "\(limit) · \(types)"
    }

    private func add(_ urls: [URL]) {
        Task {
            let accepted = await model.attachmentURLsWithinDiscordLimit(urls)
            form.addFiles(accepted, to: control)
        }
    }
}

/// Wraps chips onto as many lines as they need.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var originY = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var originX = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: originX, y: originY), proposal: ProposedViewSize(size))
                originX += size.width + spacing
            }
            originY += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty,
               rows[rows.count - 1].width + spacing + size.width > width
            {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

private struct InteractionModalSelectChevron: View {
    let isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.callout.weight(.semibold))
            .foregroundStyle(isOpen ? AnyShapeStyle(SakuraCordAccentColor.color) : AnyShapeStyle(.secondary))
            .rotationEffect(.degrees(isOpen ? 180 : 0))
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.86), value: isOpen)
            .accessibilityHidden(true)
    }
}
