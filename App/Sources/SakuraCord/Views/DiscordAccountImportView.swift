import SwiftUI

enum DiscordAccountImportState {
    case loading
    case accounts([DiscordImportAccount])
    case failed(String)
}

/// Presentation for the import step; navigation and authentication stay with
/// DiscordLoginView, just like the MFA step.
struct DiscordAccountImportView: View {
    let state: DiscordAccountImportState
    let savedAccountIDs: Set<String>
    let importingAccountID: String?
    let errorMessage: String?
    let isTransitioning: Bool
    let goBack: () -> Void
    let retry: () -> Void
    let selectAccount: (DiscordImportAccount) -> Void

    private let rowShape = RoundedRectangle(
        cornerRadius: SakuraCordAuthenticationMetrics.controlRadius, style: .continuous
    )

    var body: some View {
        VStack(spacing: 28) {
            header
            Group {
                switch state {
                case .loading:
                    loadingAccounts
                case let .accounts(accounts):
                    let available = accounts.filter { !savedAccountIDs.contains($0.id) }
                    if available.isEmpty {
                        emptyState
                    } else {
                        accountList(available)
                    }
                case let .failed(message):
                    failureState(message)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .onExitCommand(perform: goBack)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Import from Discord")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text("Bring an account already signed in on this Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .disabled(importingAccountID != nil || isTransitioning)
            .help("Back to sign in")
            .accessibilityLabel("Back to sign in")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var loadingAccounts: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ForEach(0 ..< 3) { _ in
                    HStack(spacing: 14) {
                        Circle().fill(.quaternary).frame(width: 48, height: 48)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(width: 150, height: 12)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 76)
                }
            }
            .background(.regularMaterial, in: rowShape)
            .authenticationLoading(true, in: rowShape)
            .accessibilityHidden(true)
            Text("Finding your accounts…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func accountList(_ accounts: [DiscordImportAccount]) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.72))
                            .frame(height: 1)
                            .padding(.leading, 80)
                    }
                    accountRow(account)
                }
            }
            .background(.regularMaterial, in: rowShape)
            .overlay { rowShape.stroke(.primary.opacity(0.11), lineWidth: 1) }
            Text(importingAccountID == nil ? "Choose an account to continue." : "Signing in…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private func accountRow(_ account: DiscordImportAccount) -> some View {
        let isImporting = importingAccountID == account.id
        return HStack(spacing: 14) {
            AvatarView(name: account.username, url: account.avatarURL, size: 48,
                       maximumPixelDimension: 96, animates: false)
            Text(account.username)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if isImporting {
                Text("Signing in…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 78)
            } else {
                Button("Import") { selectAccount(account) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(SakuraCordAccentColor.color)
                    .disabled(importingAccountID != nil || isTransitioning)
                    .frame(width: 78)
                    .accessibilityLabel("Import \(account.username)")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 76)
        .authenticationLoading(isImporting, in: rowShape)
        .accessibilityValue(isImporting ? "Signing in" : "")
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(SakuraCordAccentColor.color)
            Text("You're all set.")
                .font(.headline)
            Text("All accounts signed in to Discord are already in SakuraCord.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Back to sign in", action: goBack)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(SakuraCordAccentColor.color)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: retry)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(SakuraCordAccentColor.color)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
    }
}
