import SakuraCordModels
import SwiftUI

/// Keeps folder edits local until Done, with Discord's 32-character name limit
/// and the default color represented by an absent color value.
struct ServerFolderSettingsView: View {
    static let defaultColor: UInt32 = 0x5865F2
    static let maximumNameLength = 32

    let save: (_ name: String, _ colorHex: UInt32?) -> Void
    @Environment(\.windowModalContext) private var modal
    @State private var name: String
    @State private var color: UInt32?

    init(folder: GuildFolder, save: @escaping (_ name: String, _ colorHex: UInt32?) -> Void) {
        self.save = save
        _name = State(initialValue: folder.name ?? "")
        _color = State(initialValue: folder.colorHex == Self.defaultColor ? nil : folder.colorHex)
    }

    var body: some View {
        VStack(spacing: 0) {
            ServerFolderNameField(name: $name, submit: done)
                .padding(.horizontal, InterfaceScale.metric(16)).padding(.top, InterfaceScale.metric(8))
            ServerFolderColorEditor(color: $color)
                .padding(.horizontal, InterfaceScale.metric(16)).padding(.top, InterfaceScale.metric(16))
            Divider()
            ServerFolderSettingsFooter(cancel: { modal?.dismiss() }, done: done)
        }
        .windowModalSize(width: 390)
    }

    private func done() {
        save(name, color)
        modal?.dismiss()
    }
}

private struct ServerFolderNameField: View {
    @Binding var name: String
    let submit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceScale.metric(8)) {
            Text("Folder Name").font(.interface(.headline))
            TextField("Server Folder", text: $name)
                .textFieldStyle(.plain).font(.interface(.body))
                .focused($isFocused)
                .onSubmit(submit)
                .padding(InterfaceScale.metric(14)).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(ModalInputSurface(isFocused: isFocused) { isFocused = true })
                .onChange(of: name) { _, value in
                    if value.count > ServerFolderSettingsView.maximumNameLength {
                        name = String(value.prefix(ServerFolderSettingsView.maximumNameLength))
                    }
                }
        }
        .task {
            await Task.yield()
            isFocused = true
        }
    }
}

private struct ServerFolderColorEditor: View {
    @Binding var color: UInt32?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Folder Color").font(.interface(.headline))
                Spacer()
                Button("Default") { color = nil }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(color == nil)
            }
            SakuraCordColorPicker(color: Binding(
                get: { color ?? ServerFolderSettingsView.defaultColor },
                set: { color = $0 == ServerFolderSettingsView.defaultColor ? nil : $0 }
            ))
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ServerFolderSettingsFooter: View {
    let cancel: () -> Void
    let done: () -> Void

    var body: some View {
        HStack {
            ModalGlassButton(symbol: "xmark", label: "Cancel", action: cancel)
            Spacer(minLength: InterfaceScale.metric(16))
            ModalGlassButton(symbol: "checkmark", label: "Done", primary: true, action: done)
                .keyboardShortcut(.defaultAction)
        }
        .padding(InterfaceScale.metric(12))
    }
}
