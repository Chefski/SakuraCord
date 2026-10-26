import SakuraCordModels
import SwiftUI

/// Keyed by user so switching between Ignore and Block updates the open modal in place.
struct RelationshipConfirmationPresentation: Identifiable {
    let confirmation: FriendsConfirmation
    let user: User
    var id: UserID { user.id }

    init?(_ confirmation: FriendsConfirmation?) {
        guard let confirmation else { return nil }
        switch confirmation {
        case .ignore(let user, _), .block(let user): self.user = user
        case .removeFriend, .acceptStranger: return nil
        }
        self.confirmation = confirmation
    }
}

/// Ignore and Block confirmations, modeled on Discord's relationship modals with less copy.
struct RelationshipConfirmationView: View {
    let model: AppModel
    let user: User
    @State private var confirmation: FriendsConfirmation
    // Block confirmations carry no Ignore origin; switching from Block uses the generic menu location.
    @State private var ignoreLocation: IgnoreActionLocation
    @Environment(\.windowModalContext) private var modal
    @Environment(\.windowModalAvailableSize) private var availableSize

    init(model: AppModel, presentation: RelationshipConfirmationPresentation) {
        self.model = model
        user = presentation.user
        _confirmation = State(initialValue: presentation.confirmation)
        if case .ignore(_, let location) = presentation.confirmation {
            _ignoreLocation = State(initialValue: location)
        } else {
            _ignoreLocation = State(initialValue: .contextMenu)
        }
    }

    private var isBlock: Bool {
        if case .block = confirmation { true } else { false }
    }

    private var title: String {
        "\(isBlock ? "Block" : "Ignore") \(model.friendDisplayName(user))?"
    }

    private var effects: [String] {
        if isBlock {
            ["Stops direct messages", "Limits access to your profile and activity"]
                + (model.isFriend(user.id) ? ["Removes them as a friend"] : [])
        } else {
            ["Hides their messages and profile", "Mutes their notifications and activity"]
        }
    }

    private var alternative: FriendsConfirmation? {
        if isBlock {
            model.isUserIgnored(user.id) ? nil : .ignore(user, ignoreLocation)
        } else {
            .block(user)
        }
    }

    var body: some View {
        VStack(spacing: InterfaceScale.metric(16)) {
            VStack(spacing: InterfaceScale.metric(10)) {
                AvatarView(name: user.displayName, url: user.avatarURL, size: InterfaceScale.metric(64))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: isBlock ? "nosign" : "eye.slash")
                            .font(.interface(.caption).weight(.bold))
                            .frame(width: InterfaceScale.metric(24), height: InterfaceScale.metric(24))
                            .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                            .overlay { Circle().stroke(.separator, lineWidth: 1) }
                            .offset(x: InterfaceScale.metric(4), y: InterfaceScale.metric(4))
                    }
                    .accessibilityHidden(true)
                Text(title)
                    .font(.interface(.title2).weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: InterfaceScale.metric(10)) {
                ForEach(effects, id: \.self) { effect in
                    RelationshipConfirmationRow(symbol: "checkmark.circle.fill", text: effect)
                }
                RelationshipConfirmationRow(
                    symbol: isBlock ? "exclamationmark.triangle.fill" : "info.circle.fill",
                    text: isBlock ? "They can still see you in group DMs and servers." : "They can still message you and won’t be notified.",
                    isCaveat: true
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, InterfaceScale.metric(12))
            if let alternative {
                Button(isBlock ? "Ignore Instead" : "Block Instead") {
                    confirmation = alternative
                    model.friends.confirmation = alternative
                }
                .buttonStyle(.link)
            }
            // Keep the 12-point footer inset that makes the capsules concentric with the panel.
            HStack {
                ModalGlassButton(symbol: "xmark", label: "Cancel") { modal?.dismiss() }
                Spacer(minLength: InterfaceScale.metric(16))
                ModalGlassButton(
                    symbol: isBlock ? "nosign" : "eye.slash",
                    label: isBlock ? "Block" : "Ignore",
                    primary: true,
                    destructive: isBlock
                ) { model.confirmFriendsAction(confirmation) }
                    .disabled(model.friends.pendingUserIDs.contains(user.id))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, InterfaceScale.metric(4))
        }
        .padding(.top, InterfaceScale.metric(20))
        .padding(InterfaceScale.metric(12))
        .frame(width: min(InterfaceScale.metric(360), availableSize.width))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct RelationshipConfirmationRow: View {
    let symbol: String
    let text: String
    var isCaveat = false

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(isCaveat ? AnyShapeStyle(.secondary) : AnyShapeStyle(SakuraCordAccentColor.color))
        }
        .font(.interface(isCaveat ? .callout : .body))
        .foregroundStyle(isCaveat ? .secondary : .primary)
        .accessibilityElement(children: .combine)
    }
}
