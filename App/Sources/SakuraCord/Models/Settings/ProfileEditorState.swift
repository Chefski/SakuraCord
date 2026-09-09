import DiscordProtocol
import Foundation
import Observation
import SakuraCordModels

@Observable
@MainActor
final class ProfileEditorState {
    private(set) var scope: ProfileEditingScope = .main
    private(set) var snapshot: ProfileEditingSnapshot?
    private(set) var inventory: ProfileCollectibleInventory?
    private(set) var history: [ProfileAvatarHistoryEntry] = []
    private(set) var changes = ProfileEditChanges()
    private var widgetDraft: [ProfileWidget]?
    private(set) var draftGeneration = UUID()
    private(set) var widgetCatalogue: [ProfileApplicationWidget] = []
    private(set) var widgetResources: ProfileWidgetResources?
    var gameSuggestions = ProfileEditorGameSuggestions()
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var requiresReload = false
    var errorMessage: String?
    var fieldErrors: [String: [String]] = [:]
    var showsUnsavedReminder = false
    var avatarPreviewURL: URL?
    var bannerPreviewURL: URL?
    var selectedServerTag: PrimaryGuildIdentity?

    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var session: AppModelAccountSession?
    @ObservationIgnored let model: AppModel
    @ObservationIgnored private var ownedPreviewURLs: Set<URL> = []

    init(model: AppModel) { self.model = model }

    deinit {
        for url in ownedPreviewURLs { try? FileManager.default.removeItem(at: url) }
    }

    var hasChanges: Bool { changes.hasChanges }
    var isNitro: Bool { snapshot?.widgetEligibility.hasFullNitro == true }
    var canSave: Bool { snapshot != nil && hasChanges && !isSaving && !isLoading && !requiresReload && bio.utf16.count <= 300 && widgetsAreValid }
    var canEditWidgets: Bool { snapshot?.widgetEligibility.canEditPersonalWidget == true && !isSaving && !requiresReload }
    var hasAvatarSelection: Bool {
        switch changes.identity.avatar {
        case .unchanged: snapshot?.identity.avatarHash.value != nil
        case .clear: false
        case .set: true
        }
    }
    var hasBannerSelection: Bool {
        switch changes.metadata.banner {
        case .unchanged: snapshot?.metadata.bannerHash.value != nil
        case .clear: false
        case .set: true
        }
    }
    var hasNameStyleSelection: Bool {
        changes.identity.displayNameStyle.applying(to: snapshot?.identity.displayNameStyle ?? .missing).value != nil
    }

    func selectedCollectibleID(_ kind: ProfileCollectibleKind) -> String? {
        switch kind {
        case .avatarDecoration: changes.identity.decorationSKUID.applying(to: snapshot?.identity.decorationSKUID ?? .missing).value
        case .nameplate: changes.identity.nameplateSKUID.applying(to: snapshot?.identity.nameplateSKUID ?? .missing).value
        case .effect, .frame:
            switch changes.metadata.collectibleSKUIDs {
            case .unchanged: snapshot?.metadata.collectibles.value?.first { $0.type == kind.rawValue }?.skuID
            case .clear: nil
            case let .set(ids): ids.first { id in
                inventory?.item(id: id)?.kind == kind || snapshot?.metadata.collectibles.value?.contains { $0.skuID == id && $0.type == kind.rawValue } == true
            }
            }
        }
    }
    var widgets: [ProfileWidget] { widgetDraft ?? snapshot?.presentation.widgets ?? [] }
    private var widgetsAreValid: Bool {
        widgets.filter { !$0.isDiscardable }.allSatisfy { widget in
            switch widget.content {
            case let .personal(personal):
                !personal.header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && personal.header.utf16.count <= 50
            case let .games(kind, entries): entries.count <= kind.capacity && entries.allSatisfy { ($0.comment?.utf16.count ?? 0) <= 200 }
            case .application, .unrecognized: true
            }
        }
    }
    var preview: UserProfile? {
        snapshot.map {
            var result = ProfileDraftProjection.resolve(
                snapshot: $0, changes: changes, inventory: inventory,
                avatarUploadURL: avatarPreviewURL, bannerUploadURL: bannerPreviewURL, serverTag: selectedServerTag
            )
            if let widgetDraft { result.widgets = widgetDraft }
            if let widgetResources { result.widgetResources = widgetResources }
            return result
        }
    }

    var name: String {
        get { changes.identity.name.applying(to: snapshot?.identity.name ?? .missing).value ?? "" }
        set { changes.identity.name = textChange(newValue, original: snapshot?.identity.name); fieldErrors["global_name"] = nil; fieldErrors["nick"] = nil }
    }

    var bio: String {
        get { changes.metadata.bio.applying(to: snapshot?.metadata.bio ?? .missing).value ?? "" }
        set { changes.metadata.bio = textChange(newValue, original: snapshot?.metadata.bio); fieldErrors["bio"] = nil }
    }

    var pronouns: String {
        get { changes.metadata.pronouns.applying(to: snapshot?.metadata.pronouns ?? .missing).value ?? "" }
        set { changes.metadata.pronouns = textChange(newValue, original: snapshot?.metadata.pronouns); fieldErrors["pronouns"] = nil }
    }

    func loadIfNeeded(preferCached: Bool = false, refreshExisting: Bool = false) async {
        if let session, model.isCurrentAccountSession(session), snapshot != nil {
            guard refreshExisting, !hasChanges, !isSaving, !requiresReload else { return }
            await load(scope, preferCached: preferCached)
            return
        }
        await load(preferCached: preferCached)
    }

    func load(_ requestedScope: ProfileEditingScope = .main, preferCached: Bool = false) async {
        if let previous = session, !model.isCurrentAccountSession(previous) {
            revision = UUID()
            isSaving = false
            inventory = nil
            history = []
            widgetCatalogue = []
            widgetResources = nil
            gameSuggestions = ProfileEditorGameSuggestions()
            snapshot = nil
            resetDraft()
        }
        guard !isSaving else { return }
        if hasChanges, !requiresReload {
            showsUnsavedReminder = true
            return
        }
        let requestRevision = UUID()
        let remainingChanges = requiresReload && requestedScope == scope ? changes : ProfileEditChanges()
        if !requiresReload || requestedScope != scope { widgetDraft = nil }
        revision = requestRevision
        draftGeneration = UUID()
        let account = model.accountSession()
        session = account
        scope = requestedScope
        snapshot = nil
        changes = remainingChanges
        errorMessage = nil
        fieldErrors = [:]
        isLoading = true
        defer { if revision == requestRevision { isLoading = false } }
        do {
            let cached = preferCached ? try await account.provider.cachedProfileEditingSnapshot(in: requestedScope) : nil
            let value: ProfileEditingSnapshot
            if let cached { value = cached } else { value = try await account.provider.profileEditingSnapshot(in: requestedScope) }
            guard isCurrent(account, revision: requestRevision) else { return }
            snapshot = value
            widgetResources = value.presentation.widgetResources
            requiresReload = false
        } catch {
            guard isCurrent(account, revision: requestRevision) else { return }
            DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
            errorMessage = error.localizedDescription
        }
    }

    func loadInventory() async throws {
        guard inventory == nil, let session, model.isCurrentAccountSession(session) else { return }
        let requestRevision = revision
        let value = try await session.provider.profileCollectibleInventory()
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        inventory = value
    }

    func loadHistory() async throws {
        guard let session, model.isCurrentAccountSession(session) else { throw CancellationError() }
        let requestRevision = revision
        let value = try await session.provider.profileAvatarHistory()
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        history = value
    }

    func loadWidgetCatalogue() async throws {
        guard let session, model.isCurrentAccountSession(session), let userID = snapshot?.presentation.id else { throw CancellationError() }
        let requestRevision = revision
        async let featured = session.provider.profileWidgetCatalogue(developer: false)
        async let identities = session.provider.profileWidgetApplicationIdentities(for: userID)
        let developer = snapshot?.widgetEligibility.showsDeveloperWidgets == true ? try await session.provider.profileWidgetCatalogue(developer: true) : []
        let (featuredWidgets, loadedIdentities) = try await (featured, identities)
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        var seen = Set<String>()
        widgetCatalogue = (featuredWidgets + developer).filter { seen.insert($0.id).inserted }
        let applicationIDs = (widgetCatalogue + (widgetResources?.applications ?? [])).map { $0.connectionApplicationID ?? $0.applicationID }
        let connections = try await session.provider.profileWidgetConnections(applicationIDs: applicationIDs)
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        var resources = widgetResources ?? ProfileWidgetResources()
        let catalogueIDs = Set(widgetCatalogue.map(\.id))
        resources.applications = widgetCatalogue + resources.applications.filter { !catalogueIDs.contains($0.id) }
        resources.identities = loadedIdentities
        resources.connections = connections
        widgetResources = resources
    }

    func loadWidgetSuggestionsIfNeeded() async {
        guard canEditWidgets, !gameSuggestions.hasAttemptedLoad,
              let session, model.isCurrentAccountSession(session) else { return }
        let requestRevision = revision
        let suggestions = gameSuggestions
        suggestions.hasAttemptedLoad = true
        suggestions.isLoading = true
        defer { suggestions.isLoading = false }
        do {
            let feeds = try await session.provider.suggestedProfileWidgetGames()
            guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
            suggestions.load(feeds, existing: widgets)
        } catch is CancellationError { suggestions.hasAttemptedLoad = false } catch {
            DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
            suggestions.errorMessage = error.localizedDescription
        }
    }

    func refreshWidgetConnections() async {
        guard let session, model.isCurrentAccountSession(session), let userID = snapshot?.presentation.id,
              let resources = widgetResources, !resources.applications.isEmpty else { return }
        let requestRevision = revision
        do {
            let connections = try await session.provider.profileWidgetConnections(applicationIDs: resources.applications.map { $0.connectionApplicationID ?? $0.applicationID })
            let identities = try await session.provider.profileWidgetApplicationIdentities(for: userID)
            guard isCurrent(session, revision: requestRevision) else { return }
            widgetResources?.connections = connections
            widgetResources?.identities = identities
        } catch is CancellationError { return } catch {
            guard isCurrent(session, revision: requestRevision) else { return }
            DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
            errorMessage = error.localizedDescription
        }
    }

    func resolveWidgetSuggestions(for kind: ProfileGameWidgetKind) async {
        let suggestions = gameSuggestions
        guard suggestions.isLoaded else { return }
        let ids = suggestions.visibleIDs[kind, default: []] + suggestions.peekIDs(for: kind)
        guard !ids.isEmpty else { return }
        do {
            let games = try await loadWidgetGames(ids: ids)
            let available = Set(games.filter { $0.coverURL != nil }.map(\.id))
            suggestions.removeUnavailable(ids: Set(ids).subtracting(available), for: kind)
            suggestions.errorMessage = nil
        } catch is CancellationError { return } catch {
            DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
            suggestions.errorMessage = error.localizedDescription
        }
    }

    func defaultWidgetGames() async throws -> [ProfileGame] {
        guard let session, model.isCurrentAccountSession(session) else { throw CancellationError() }
        let requestRevision = revision
        let games = try await session.provider.defaultProfileWidgetGames()
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        var resources = widgetResources ?? ProfileWidgetResources()
        let ids = Set(games.map(\.id))
        resources.games.removeAll { ids.contains($0.id) }
        resources.games += games
        widgetResources = resources
        return games
    }

    func searchWidgetGames(query: String) async throws -> [ProfileGame] {
        guard let session, model.isCurrentAccountSession(session) else { throw CancellationError() }
        let requestRevision = revision
        let games = try await session.provider.searchProfileWidgetGames(query: query)
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        return games
    }

    @discardableResult
    func loadWidgetGames(ids: [String]) async throws -> [ProfileGame] {
        guard let session, model.isCurrentAccountSession(session) else { throw CancellationError() }
        let requestRevision = revision
        let games = try await session.provider.profileWidgetGames(ids: ids)
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        var resources = widgetResources ?? ProfileWidgetResources()
        let newIDs = Set(games.map(\.id))
        resources.games.removeAll { newIDs.contains($0.id) }
        resources.games += games
        widgetResources = resources
        return games
    }

    func uploadWidgetImage(fileURL: URL, filename: String, contentType: String) async throws -> ProfileWidgetImage {
        guard canEditWidgets, let session, model.isCurrentAccountSession(session) else { throw CancellationError() }
        let requestRevision = revision
        let generation = draftGeneration
        let image = try await session.provider.uploadProfileWidgetImage(fileURL: fileURL, filename: filename, contentType: contentType)
        guard isCurrent(session, revision: requestRevision), draftGeneration == generation else { throw CancellationError() }
        ownedPreviewURLs.insert(fileURL)
        return image
    }

    func deleteHistory(_ entry: ProfileAvatarHistoryEntry) async throws {
        guard let session, model.isCurrentAccountSession(session) else { throw CancellationError() }
        let requestRevision = revision
        try await session.provider.deleteProfileAvatarHistoryEntry(id: entry.id)
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        history.removeAll { $0.id == entry.id }
    }

    func save() async {
        guard canSave else { return }
        await saveChanges(changes)
    }

    func saveGameWidgetShortcut(gameID: String, kind: ProfileGameWidgetKind) async {
        guard scope == .main, canEditWidgets, !isLoading else { return }
        if let widget = widgets.first(where: { if case let .games(value, _) = $0.content { value == kind } else { false } }),
           case let .games(_, games) = widget.content {
            if games.contains(where: { $0.id == gameID }) { removeWidgetGame(widgetID: widget.id, gameID: gameID) } else {
                guard games.count < kind.capacity else { return }
                addWidgetGame(widgetID: widget.id, gameID: gameID)
            }
        } else { addWidget(ProfileWidget(content: .games(kind, [ProfileWidgetGame(id: gameID)]))) }
        guard widgetsAreValid else {
            errorMessage = "Finish editing the other widgets before saving this game."
            return
        }
        var widgetChanges = ProfileEditChanges()
        widgetChanges.widgets = widgets.filter { !$0.isDiscardable }
        await saveChanges(widgetChanges)
    }

    private func saveChanges(_ submittedChanges: ProfileEditChanges) async {
        guard let session, model.isCurrentAccountSession(session) else { return }
        let requestRevision = revision
        isSaving = true
        errorMessage = nil
        fieldErrors = [:]
        defer { if revision == requestRevision { isSaving = false } }
        do {
            try await session.provider.saveProfileChanges(submittedChanges, in: scope) { [weak self] confirmation in
                await self?.acknowledge(confirmation, account: session, revision: requestRevision)
            }
            guard isCurrent(session, revision: requestRevision) else { return }
            showsUnsavedReminder = false
        } catch {
            guard isCurrent(session, revision: requestRevision) else { return }
            errorMessage = error.localizedDescription
            if let validation = error as? ProfileValidationError { fieldErrors = validation.fields }
            if let failure = error as? ProfileSaveFailure {
                fieldErrors = failure.fields
                requiresReload = requiresReload || failure.requiresReload
            }
            if error is URLError || error is CancellationError { requiresReload = true }
        }
    }

    func resetDraft() {
        guard !isSaving else { return }
        draftGeneration = UUID()
        for url in ownedPreviewURLs { try? FileManager.default.removeItem(at: url) }
        ownedPreviewURLs.removeAll()
        changes = ProfileEditChanges()
        widgetDraft = nil
        avatarPreviewURL = nil
        bannerPreviewURL = nil
        selectedServerTag = nil
        errorMessage = nil
        fieldErrors = [:]
        showsUnsavedReminder = false
    }

    func setStyle(_ style: DisplayNameStyle?) {
        changes.identity.displayNameStyle = change(style, original: snapshot?.identity.displayNameStyle)
    }

    func setServerTag(_ identity: PrimaryGuildIdentity?) {
        guard scope == .main else { return }
        let original = snapshot?.serverTag.value
        let originalID = original?.isEnabled.value == true ? original?.guildID.value : nil
        let selectedID = identity?.guildID
        selectedServerTag = identity
        changes.serverTag = selectedID == originalID ? .unchanged : selectedID.map(ProfileChange.set) ?? .clear
    }

    func receiveCustomStatus(_ status: ProfileCustomStatus?) {
        snapshot?.customStatus = status
        snapshot?.presentation.customStatus = status?.displayText
        snapshot?.mainPresentation.customStatus = status?.displayText
    }

    func saveCustomStatus(_ status: ProfileCustomStatus?) async throws {
        guard !isSaving, let session, model.isCurrentAccountSession(session) else { throw CancellationError() }
        let requestRevision = revision
        isSaving = true
        defer { if revision == requestRevision { isSaving = false } }
        let saved = try await session.provider.updateProfileCustomStatus(status)
        guard isCurrent(session, revision: requestRevision) else { throw CancellationError() }
        receiveCustomStatus(saved)
    }

    func setWidgets(_ value: [ProfileWidget]) {
        guard canEditWidgets else { return }
        widgetDraft = value
        let saveable = value.filter { !$0.isDiscardable }
        let original = snapshot?.presentation.widgets ?? []
        let unchanged = saveable.count == original.count && zip(saveable, original).allSatisfy { $0.hasSameEditableContent(as: $1) }
        changes.widgets = unchanged ? nil : saveable
        fieldErrors["widgets"] = nil
    }

    func addWidget(_ widget: ProfileWidget) {
        setWidgets([widget] + widgets)
    }

    func updateWidget(_ widget: ProfileWidget) {
        guard let index = widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        var updated = widgets
        updated[index] = widget
        setWidgets(updated)
    }

    func removeWidget(id: String) {
        setWidgets(widgets.filter { $0.id != id })
    }

    func addWidgetGame(widgetID: String, gameID: String) {
        guard var widget = widgets.first(where: { $0.id == widgetID }),
              case let .games(kind, games) = widget.content, games.count < kind.capacity,
              !games.contains(where: { $0.id == gameID }) else { return }
        widget.content = .games(kind, [ProfileWidgetGame(id: gameID)] + games)
        updateWidget(widget)
    }

    func updateWidgetGame(widgetID: String, game: ProfileWidgetGame) {
        guard var widget = widgets.first(where: { $0.id == widgetID }),
              case let .games(kind, games) = widget.content,
              let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        var updated = games
        updated[index] = game
        widget.content = .games(kind, updated)
        updateWidget(widget)
    }

    func removeWidgetGame(widgetID: String, gameID: String) {
        guard var widget = widgets.first(where: { $0.id == widgetID }),
              case let .games(kind, games) = widget.content else { return }
        widget.content = .games(kind, games.filter { $0.id != gameID })
        updateWidget(widget)
    }

    func moveWidgetGame(widgetID: String, gameID: String, to target: Int) {
        guard var widget = widgets.first(where: { $0.id == widgetID }),
              case let .games(kind, games) = widget.content,
              let index = games.firstIndex(where: { $0.id == gameID }), games.indices.contains(target) else { return }
        var updated = games
        updated.insert(updated.remove(at: index), at: target)
        widget.content = .games(kind, updated)
        updateWidget(widget)
    }

    func restoreWidgetGameOrder(widgetID: String, ids: [String]) {
        guard var widget = widgets.first(where: { $0.id == widgetID }),
              case let .games(kind, games) = widget.content else { return }
        let ordered = ids.compactMap { id in games.first { $0.id == id } }
        widget.content = .games(kind, ordered + games.filter { !ids.contains($0.id) })
        updateWidget(widget)
    }

    func moveWidget(id: String, to index: Int) {
        var updated = widgets
        guard let oldIndex = updated.firstIndex(where: { $0.id == id }) else { return }
        let moved = updated.remove(at: oldIndex)
        updated.insert(moved, at: min(max(0, index), updated.count))
        setWidgets(updated)
    }

    func setTheme(_ colors: ProfileThemeColors?) {
        changes.metadata.themeColors = change(colors, original: snapshot?.metadata.themeColors)
    }

    func setAvatar(_ selection: ProfileAvatarSelection?, previewURL: URL? = nil) {
        releasePreview(avatarPreviewURL)
        if case .upload = selection, let previewURL, previewURL.isFileURL { ownedPreviewURLs.insert(previewURL) }
        changes.identity.avatar = selection.map(ProfileChange.set) ?? (snapshot?.identity.avatarHash.value == nil ? .unchanged : .clear)
        avatarPreviewURL = previewURL
    }

    func setBanner(_ upload: ProfileImageUpload?, previewURL: URL? = nil) {
        releasePreview(bannerPreviewURL)
        if upload != nil, let previewURL, previewURL.isFileURL { ownedPreviewURLs.insert(previewURL) }
        changes.metadata.banner = upload.map(ProfileChange.set) ?? (snapshot?.metadata.bannerHash.value == nil ? .unchanged : .clear)
        bannerPreviewURL = previewURL
    }

    func setCollectible(_ item: ProfileCollectibleItem?, kind: ProfileCollectibleKind) {
        switch kind {
        case .avatarDecoration:
            changes.identity.decorationSKUID = change(item?.id, original: snapshot?.identity.decorationSKUID)
        case .nameplate:
            changes.identity.nameplateSKUID = change(item?.id, original: snapshot?.identity.nameplateSKUID)
        case .effect, .frame:
            var ids: [String]
            switch changes.metadata.collectibleSKUIDs {
            case .unchanged: ids = snapshot?.metadata.collectibles.value?.map(\.skuID) ?? []
            case .clear: ids = []
            case let .set(value): ids = value
            }
            let originalItems = snapshot?.metadata.collectibles.value ?? []
            ids.removeAll { id in inventory?.item(id: id)?.kind == kind || originalItems.contains { $0.skuID == id && $0.type == kind.rawValue } }
            if let item { ids.append(item.id) }
            changes.metadata.collectibleSKUIDs = ids == (snapshot?.metadata.collectibles.value?.map(\.skuID) ?? []) ? .unchanged : .set(ids)
        }
    }

    private func acknowledge(_ confirmation: ProfileSaveConfirmation, account: AppModelAccountSession, revision: UUID) {
        guard isCurrent(account, revision: revision) else { return }
        changes.acknowledge(confirmation.stage)
        if confirmation.stage == .widgets { widgetDraft = nil }
        if let value = confirmation.snapshot {
            snapshot = value
            if confirmation.stage == .identity { releasePreview(avatarPreviewURL); avatarPreviewURL = nil }
            if confirmation.stage == .metadata { releasePreview(bannerPreviewURL); bannerPreviewURL = nil }
        } else {
            requiresReload = true
        }
    }

    private func releasePreview(_ url: URL?) {
        guard let url, ownedPreviewURLs.remove(url) != nil else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func isCurrent(_ account: AppModelAccountSession, revision: UUID) -> Bool {
        self.revision == revision && model.isCurrentAccountSession(account)
    }

    private func textChange(_ value: String, original: ProfileStoredValue<String>?) -> ProfileChange<String> {
        if value == (original?.value ?? "") { return .unchanged }
        return .set(value)
    }

    private func change<Value: Hashable & Sendable>(_ value: Value?, original: ProfileStoredValue<Value>?) -> ProfileChange<Value> {
        if value == original?.value { return .unchanged }
        return value.map(ProfileChange.set) ?? .clear
    }
}
