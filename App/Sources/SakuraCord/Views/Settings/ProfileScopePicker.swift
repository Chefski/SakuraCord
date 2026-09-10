import SakuraCordModels
import SwiftUI

struct ProfileScopePicker: View {
    let scope: ProfileEditingScope
    let guilds: [Guild]
    let nicknames: [GuildID: String]
    let select: (ProfileEditingScope) -> Void
    @State private var isPresented = false

    private var selectedGuild: Guild? {
        scope.guildID.flatMap { id in guilds.first { $0.id == id } }
    }

    private var title: String {
        selectedGuild?.name ?? String(localized: "Main Profile", bundle: #bundle)
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                ProfileScopeIcon(name: title, iconURL: selectedGuild?.iconURL, isMain: scope == .main)
                Text(title).lineLimit(1)
                Image(systemName: isPresented ? "chevron.up" : "chevron.down").font(.caption.bold())
            }
            .frame(maxWidth: 240)
            .contentShape(Rectangle())
        }
        .escapeDismissiblePopover(isPresented: $isPresented) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ProfileScopeRow(name: String(localized: "Main Profile", bundle: #bundle), iconURL: nil, isMain: true,
                                    nickname: nil, isSelected: scope == .main) { choose(.main) }
                    ForEach(guilds) { guild in
                        ProfileScopeRow(name: guild.name, iconURL: guild.iconURL, nickname: nicknames[guild.id],
                                        isSelected: scope == .server(guild.id)) { choose(.server(guild.id)) }
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.visible)
            .frame(width: 264, height: min(217, CGFloat(guilds.count + 1) * 40 + 8))
        }
    }

    private func choose(_ value: ProfileEditingScope) {
        isPresented = false
        guard value != scope else { return }
        select(value)
    }
}

private struct ProfileScopeIcon: View {
    let name: String
    let iconURL: URL?
    let isMain: Bool

    var body: some View {
        Group {
            if isMain {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
            } else {
                AvatarView(name: name, url: iconURL, size: 20)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

private struct ProfileScopeRow: View {
    let name: String
    let iconURL: URL?
    var isMain = false
    let nickname: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ProfileScopeIcon(name: name, iconURL: iconURL, isMain: isMain)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).lineLimit(1)
                    if let nickname, !nickname.isEmpty { Text(nickname).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                if isSelected { Image(systemName: "checkmark").font(.body.bold()) }
            }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverRowButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
