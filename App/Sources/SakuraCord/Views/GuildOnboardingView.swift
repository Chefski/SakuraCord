import SakuraCordModels
import SwiftUI

struct GuildOnboardingView: View {
    let model: AppModel
    let guildID: GuildID
    @Environment(\.windowModalContext) private var dismiss
    @Environment(\.windowModalAvailableSize) private var availableSize
    @State private var showsChannels = false
    @State private var contentHeight: CGFloat = 300

    private var entry: GuildOnboardingStore.Entry { model.onboarding.entries[guildID] ?? .init() }
    private var working: Bool { entry.isLoading || entry.isSaving }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let notice = entry.notice { Text(notice).foregroundStyle(.secondary).font(.callout) }
                    if entry.isLoading {
                        ProgressView("Checking server…").frame(maxWidth: .infinity).padding(32)
                    } else if let configuration = entry.configuration {
                        if entry.initial { initialQuestions(configuration) } else { customization(configuration) }
                    } else if !working {
                        ContentUnavailableView("Unable to Load Questions", systemImage: "list.bullet.clipboard",
                                               description: Text("Refresh to check the server’s current setup."))
                    }
                }
                .padding(24)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
        }
        .frame(width: min(560, availableSize.width), height: min(entry.initial ? max(320, contentHeight + 160) : 650, availableSize.height))
        .tint(SakuraCordAccentColor.color)
        .windowModalDismissDisabled(entry.isSaving)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.initial ? "Server Onboarding" : "Channels & Roles")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.initial ? "Welcome to \(model.serverRailGuildsByID[guildID]?.name ?? "the server")" : "Channels & Roles")
                    .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if !entry.initial {
                    Text(model.serverRailGuildsByID[guildID]?.name ?? "").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button("Close", systemImage: "xmark") { dismiss?() }
                .labelStyle(.iconOnly).buttonStyle(.plain).padding(6)
                .help(entry.initial ? "Continue later" : "Close")
                .disabled(entry.isSaving)
        }
        .padding(24)
    }

    @ViewBuilder
    private func initialQuestions(_ configuration: GuildOnboarding) -> some View {
        let prompts = configuration.questions(initial: true)
        if let prompt = prompts.first(where: { $0.id == entry.promptID }) ?? prompts.first {
            Text("Question \((prompts.firstIndex { $0.id == prompt.id } ?? 0) + 1) of \(prompts.count)")
                .font(.callout).foregroundStyle(.secondary)
            question(prompt)
        } else {
            ContentUnavailableView("You’re Ready", systemImage: "checklist",
                                   description: Text("Finish joining to confirm your membership."))
        }
        if model.onboardingMember(in: guildID)?.isPending == true {
            Text("This server also requires member screening. Complete that verification in Discord to unlock messaging.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func customization(_ configuration: GuildOnboarding) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Manage channels in SakuraCord", isOn: Binding(
                get: { model.onboarding.channelManagementEnabled },
                set: { model.setChannelManagementEnabled($0); if !$0 { showsChannels = false } }
            ))
            .toggleStyle(.switch)
            if model.onboarding.channelManagementEnabled {
                Picker("Customize", selection: $showsChannels) {
                    Text("Questions").tag(false)
                    Text("Browse Channels").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            if showsChannels, model.onboarding.channelManagementEnabled {
                GuildOnboardingChannelsView(model: model, guildID: guildID, configuration: configuration)
            } else if configuration.prompts.isEmpty {
                ContentUnavailableView("No Questions", systemImage: "list.bullet",
                                       description: Text("This server hasn’t added customization questions."))
            } else {
                ForEach(configuration.prompts) { question($0) }
            }
        }
    }

    private func question(_ prompt: GuildOnboardingPrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(prompt.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(prompt.required ? "Required" : "Optional") · \(prompt.singleSelect ? "Choose one" : "Choose any")")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if prompt.options.isEmpty {
                Text("This question has no available answers. Refresh after the server updates it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(prompt.options) { option in
                OnboardingOptionRow(option: option, selected: entry.responses.contains(option.id), singleSelect: prompt.singleSelect, roles: option.roleIDs.compactMap { id in
                    (model.guildRolesByGuildID[guildID] ?? model.guildRoles).first { $0.id == id }?.name
                }) {
                    model.selectOnboardingOption(option, prompt: prompt, guildID: guildID)
                }
                .disabled(working || entry.needsRefresh)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = entry.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        HStack(spacing: 12) {
            Button("Refresh", systemImage: "arrow.clockwise") { model.refreshOnboarding(in: guildID) }
                .disabled(working)
            Spacer()
            if entry.isSaving { ProgressView().controlSize(.small) }
            if entry.initial, let configuration = entry.configuration {
                let prompts = configuration.questions(initial: true)
                let index = prompts.firstIndex { $0.id == entry.promptID } ?? 0
                if index > 0 {
                    Button("Back") { model.setOnboardingPrompt(prompts[index - 1].id, guildID: guildID) }
                        .disabled(working)
                }
                Button(index + 1 < prompts.count ? "Next" : "Finish Joining") {
                    if index + 1 < prompts.count { model.setOnboardingPrompt(prompts[index + 1].id, guildID: guildID) } else { model.saveOnboarding(in: guildID) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(working || entry.needsRefresh || !canAdvance(prompts: prompts, index: index))
            } else if entry.configuration != nil, !showsChannels {
                Button("Save Answers") { model.saveOnboarding(in: guildID) }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || entry.needsRefresh || entry.responses == Set(entry.configuration?.responses ?? []))
            }
        }
        .controlSize(.large)
        }
        .padding(20)
    }

    private func canAdvance(prompts: [GuildOnboardingPrompt], index: Int) -> Bool {
        guard prompts.indices.contains(index) else { return true }
        let prompt = prompts[index]
        let count = prompt.options.filter { entry.responses.contains($0.id) }.count
        return (!prompt.required || count > 0) && (!prompt.singleSelect || count <= 1)
    }
}

private struct OnboardingOptionRow: View {
    let option: GuildOnboardingOption
    let selected: Bool
    let singleSelect: Bool
    let roles: [String]
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let url = option.emoji?.url {
                    AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Color.clear }
                        .frame(width: 24, height: 24).accessibilityHidden(true)
                } else if let name = option.emoji?.name { Text(name).font(.title3).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title).font(.body.weight(.medium))
                    if !roles.isEmpty { Text(roles.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    if let description = option.description, !description.isEmpty {
                        Text(description).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: singleSelect
                      ? (selected ? "largecircle.fill.circle" : "circle")
                      : (selected ? "checkmark.square.fill" : "square"))
                    .foregroundStyle(selected ? SakuraCordAccentColor.color : .secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(ConcentricRectangle(cornerRadius: 16))
            .background(selected ? SakuraCordAccentColor.color.opacity(0.12) : Color.primary.opacity(hovered ? 0.08 : 0.04),
                        in: ConcentricRectangle(cornerRadius: 16))
            .overlay { ConcentricRectangle(cornerRadius: 16).stroke(selected ? SakuraCordAccentColor.color.opacity(0.7) : Color.primary.opacity(0.08)) }
        }
        .buttonStyle(.plain)
        .onModalHover { hovered = $0 }
        .accessibilityLabel(option.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(roles.isEmpty ? "" : "Roles: " + roles.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct GuildOnboardingChannelsView: View {
    let model: AppModel
    let guildID: GuildID
    let configuration: GuildOnboarding

    var body: some View {
        let settings = model.readState.notificationSettings(guildID: guildID) ?? GuildNotificationSettings(guildID: guildID)
        let enabled = settings.flags & GuildChannelSelection.enabledFlag != 0
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Show all channels", isOn: Binding(
                get: { !enabled }, set: { model.setChannelSelectionEnabled(!$0, guildID: guildID) }
            ))
            .disabled(model.onboarding.changingChannelMode)
            let channels = (model.snapshot?.channels ?? []).filter { $0.guildID == guildID }
            ForEach(ChannelGroup.make(from: channels)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    let followingCategory = group.categoryID.map { GuildChannelSelection.isSelected($0, settings: settings) } ?? false
                    if let name = group.name, let categoryID = group.categoryID {
                        Toggle("Follow \(name)", isOn: Binding(
                            get: { followingCategory },
                            set: { model.setChannelSelected($0, channelID: categoryID, guildID: guildID) }
                        ))
                        .font(.headline)
                        .disabled(!enabled || model.onboarding.changingChannels.contains(categoryID))
                    }
                    ForEach(group.channels) { channel in
                        Toggle(isOn: Binding(
                            get: { followingCategory || GuildChannelSelection.isSelected(channel.id, settings: settings) },
                            set: { model.setChannelSelected($0, channelID: channel.id, guildID: guildID) }
                        )) {
                            HStack {
                                Text(channel.name)
                                if configuration.defaultChannelIDs.contains(channel.id) {
                                    Text("Default").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!enabled || followingCategory || model.onboarding.changingChannels.contains(channel.id)
                                  || model.conversationAccess(for: channel) == .hidden)
                    }
                }
            }
        }
    }
}

struct OnboardingContinuationButton: View {
    let model: AppModel
    let guildID: GuildID
    var body: some View {
        Button { model.openChannelsAndRoles(in: guildID) } label: {
            Label("Continue Onboarding", systemImage: "checklist")
                .frame(maxWidth: .infinity).padding(10)
        }
        .buttonStyle(.borderedProminent)
        .tint(SakuraCordAccentColor.color)
        .help("Finish the server’s questions to unlock messaging")
    }
}
