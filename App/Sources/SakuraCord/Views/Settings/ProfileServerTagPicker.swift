import SakuraCordModels
import SwiftUI

struct ProfileServerTagPicker: View {
    let editor: ProfileEditorState
    let identity: PrimaryGuildIdentity?
    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        if identity?.guildID != nil || editor.snapshot?.serverTagGuilds.isEmpty == false {
            Button { isPresented.toggle() } label: {
                ProfileServerTag(identity: identity, showsDisclosure: true, isHighlighted: isHovered || isPresented)
            }
            .buttonStyle(.plain)
            .onModalHover { isHovered = $0 }
            .accessibilityLabel("Server Tag")
            .accessibilityValue(identity?.tag ?? String(localized: "No Server Tag", bundle: #bundle))
            .escapeDismissiblePopover(isPresented: $isPresented) {
                ScrollView {
                    VStack(spacing: 2) {
                        Button { editor.setServerTag(nil); isPresented = false } label: {
                            HStack {
                                Text("No Server Tag", bundle: #bundle)
                                Spacer()
                                if identity?.guildID == nil { Image(systemName: "checkmark") }
                            }
                            .padding(10).contentShape(Rectangle())
                        }
                        .buttonStyle(PopoverRowButtonStyle(isSelected: identity?.guildID == nil))
                        ForEach(editor.snapshot?.serverTagGuilds ?? []) { guild in
                            if let tag = guild.profileTag, let text = tag.tag {
                                Button { editor.setServerTag(tag); isPresented = false } label: {
                                    HStack(spacing: 8) {
                                        AvatarView(name: guild.name, url: guild.iconURL, size: 20)
                                        Text(guild.name).lineLimit(1)
                                        Spacer(minLength: 4)
                                        ProfileServerTag(identity: tag)
                                        if identity?.guildID == guild.id { Image(systemName: "checkmark") }
                                    }
                                    .padding(6).contentShape(Rectangle())
                                }
                                .buttonStyle(PopoverRowButtonStyle(isSelected: identity?.guildID == guild.id))
                                .accessibilityLabel("\(guild.name), Server Tag: \(text)")
                                .accessibilityAddTraits(identity?.guildID == guild.id ? [.isSelected] : [])
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(width: 360, height: min(400, CGFloat((editor.snapshot?.serverTagGuilds.count ?? 0) + 1) * 44 + 12))
                .onExitCommand { isPresented = false }
            }
        }
    }
}
