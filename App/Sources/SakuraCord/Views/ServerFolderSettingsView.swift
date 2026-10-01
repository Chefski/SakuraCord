import SakuraCordModels
import SwiftUI

/// Edits a server folder's name and color. The limits and palette are the
/// first-party client's: 32 characters and its twenty role colors, with the
/// default color stored as no color at all.
struct ServerFolderSettingsView: View {
    static let defaultColor: UInt32 = 0x5865F2
    static let maximumNameLength = 32
    static let palette: [UInt32] = [
        0x1ABC9C, 0x2ECC71, 0x3498DB, 0x9B59B6, 0xE91E63, 0xF1C40F, 0xE67E22, 0xE74C3C, 0x95A5A6, 0x607D8B,
        0x11806A, 0x1F8B4C, 0x206694, 0x71368A, 0xAD1457, 0xC27C0E, 0xA84300, 0x992D22, 0x979C9F, 0x546E7A,
    ]

    let folder: GuildFolder
    let save: (_ name: String, _ colorHex: UInt32?) -> Void
    @Environment(\.windowModalContext) private var modal
    @State private var name: String
    @State private var color: UInt32?
    @State private var showsColorPicker = false
    @FocusState private var nameIsFocused: Bool

    init(folder: GuildFolder, save: @escaping (_ name: String, _ colorHex: UInt32?) -> Void) {
        self.folder = folder
        self.save = save
        _name = State(initialValue: folder.name ?? "")
        _color = State(initialValue: folder.colorHex == Self.defaultColor ? nil : folder.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Folder Name").font(.headline)
                TextField("Server Folder", text: $name)
                    .textFieldStyle(.plain).font(.body)
                    .focused($nameIsFocused)
                    .onSubmit(done)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(PollInputSurface(isFocused: nameIsFocused) { nameIsFocused = true })
                    .onChange(of: name) { _, value in
                        if value.count > Self.maximumNameLength {
                            name = String(value.prefix(Self.maximumNameLength))
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Folder Color").font(.headline)
                HStack(alignment: .top, spacing: 8) {
                    swatch(Self.defaultColor, size: 48, label: "Default", isSelected: color == nil) { color = nil }
                    customSwatch
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(0 ..< 2, id: \.self) { row in
                            GridRow {
                                ForEach(Self.palette[(row * 10) ..< (row * 10 + 10)], id: \.self) { value in
                                    swatch(value, size: 20, label: String(format: "#%06X", value), isSelected: color == value) {
                                        color = value
                                    }
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { modal?.dismiss() }.buttonStyle(PollButtonStyle())
                Button("Done", action: done).buttonStyle(PollButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        // Match the modal title's 16-point inset; the width is exactly the
        // swatch row plus that inset, so every edge lines up.
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        .windowModalSize(width: 416)
        .task {
            await Task.yield()
            nameIsFocused = true
        }
    }

    private var customColor: UInt32? {
        color.flatMap { Self.palette.contains($0) ? nil : $0 }
    }

    private var customSwatch: some View {
        Button { showsColorPicker = true } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(customColor.map { Color(hex: $0) } ?? Color.clear)
                .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: customColor == nil ? "eyedropper" : "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(customColor == nil ? Color.secondary : .white)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Custom Color")
        .accessibilityLabel("Custom Color")
        .sakuraCordColorPicker(isPresented: $showsColorPicker, color: Binding(
            get: { color ?? Self.defaultColor },
            set: { color = $0 == Self.defaultColor ? nil : $0 }
        ))
    }

    private func swatch(
        _ value: UInt32,
        size: CGFloat,
        label: String,
        isSelected: Bool,
        select: @escaping () -> Void
    ) -> some View {
        Button(action: select) {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(hex: value))
                .frame(width: size, height: size)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func done() {
        save(name, color)
        modal?.dismiss()
    }
}
