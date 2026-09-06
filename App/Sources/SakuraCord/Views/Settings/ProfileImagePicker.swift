import DiscordProtocol
import MediaPipeline
import SakuraCordModels
import SwiftUI
import UniformTypeIdentifiers

struct ProfileImagePicker: View {
    let model: AppModel
    let editor: ProfileEditorState
    let purpose: ProfileImagePurpose
    let apply: (ProfileAvatarSelection, URL) -> Void

    @Environment(\.profileEditorModal) private var dismiss
    @State private var showsFileImporter = false
    @State private var showsGIFs = false
    @State private var source: ProfileImageSource?
    @State private var sourceURL: URL?
    @State private var filename = ""
    @State private var archive: ProfileAvatarHistoryEntry?
    @State private var deleteCandidate: ProfileAvatarHistoryEntry?
    @State private var work: Task<Void, Never>?
    @State private var isBusy = false
    @State private var isLoadingHistory = false
    @State private var errorMessage: String?
    @State private var temporaryFiles: [URL] = []
    private static let allowedImageTypes = ["jpg", "jpeg", "jfif", "png", "gif", "webp", "avif"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        pickerContent
        .profileEditorDismissDisabled(isBusy)
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: Self.allowedImageTypes) { result in
            switch result {
            case let .success(url): loadFile(url)
            case let .failure(error): errorMessage = error.localizedDescription
            }
        }
        .alert("Unable to Use Image", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .profileEditorOverlay(item: $deleteCandidate) { entry in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Remove Recent Avatar?", bundle: #bundle).font(.title2.bold())
                    Spacer()
                    HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { deleteCandidate = nil }
                }
                Text("This image will no longer be available in your recent avatars.", bundle: #bundle)
                Text("Pro tip: Hold Shift when removing an avatar to bypass this confirmation.", bundle: #bundle)
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { deleteCandidate = nil }
                    Button("Remove", role: .destructive) { delete(entry) }.buttonStyle(.borderedProminent)
                }
            }
            .padding(24).profileEditorModalSize(width: 400)
        }
        .task {
            guard purpose == .avatar else { return }
            isLoadingHistory = true
            defer { isLoadingHistory = false }
            do { try await editor.loadHistory() } catch { errorMessage = error.localizedDescription }
        }
        .onDisappear {
            work?.cancel()
            for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if let source, let sourceURL {
                ProfileImageCropView(image: source, imageURL: sourceURL, filename: filename, purpose: purpose,
                                     isProcessing: isBusy, canApply: canApply(source), cancel: cancelCrop, apply: process)
            } else if showsGIFs {
                VStack(spacing: 0) {
                    HStack {
                        Button { showsGIFs = false } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.plain).accessibilityLabel("Back to Images")
                        Text("Choose GIF", bundle: #bundle).font(.headline)
                        Spacer()
                        HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { dismiss?() }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    GIFPickerView(model: model, dismiss: { showsGIFs = false }, selectionHandler: chooseGIF, hidesFavorites: true)
                }
                .overlay { if isBusy { ProgressView().padding().glassEffect() } }
                .disabled(isBusy)
            } else {
                chooser
            }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Select an Image", bundle: #bundle).font(.title2.bold())
                Spacer()
                HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { dismiss?() }
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { showsFileImporter = true } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 26))
                            Text("Upload Image", bundle: #bundle).font(.headline)
                        }
                        .frame(maxWidth: .infinity).frame(height: 211)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: ConcentricRectangle(cornerRadius: 10))
                    Button { showsGIFs = true } label: {
                        ZStack {
                            LazyVGrid(columns: [.init(.flexible(), spacing: 0), .init(.flexible(), spacing: 0)], spacing: 0) {
                                ForEach(DiscordProfileImageAssets.gifPickerArtwork, id: \.self) { url in
                                    AnimatedRemoteImage(url: url, animates: false, contentMode: .fill).frame(height: 106).clipped()
                                }
                            }
                            Color.black.opacity(0.45)
                            VStack(spacing: 12) {
                                Text("GIF").font(.headline).foregroundStyle(.black).padding(4).background(.white, in: .rect(cornerRadius: 3))
                                Label("Choose GIF", systemImage: "sparkles").font(.headline)
                            }
                            .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity).frame(height: 211)
                        .clipShape(ConcentricRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            if purpose == .avatar {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Avatars", bundle: #bundle).font(.title3.bold())
                    Text("Access your 6 most recent avatar uploads.", bundle: #bundle).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(editor.history) { entry in
                            ProfileRecentAvatarButton(entry: entry, choose: { loadArchive(entry) }, remove: {
                                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { delete(entry) } else { deleteCandidate = entry }
                            })
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 56)
                    .overlay {
                        if isLoadingHistory, editor.history.isEmpty { ProgressView().controlSize(.small) }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .padding(24)
        .profileEditorModalSize(width: 480)
        .disabled(isBusy)
        .overlay { if isBusy { ProgressView().padding().glassEffect() } }
    }

    private func loadFile(_ url: URL) {
        begin {
            let permitted = url.startAccessingSecurityScopedResource()
            defer { if permitted { url.stopAccessingSecurityScopedResource() } }
            let data = try await Task.detached { try Data(contentsOf: url) }.value
            try await prepare(data, name: url.deletingPathExtension().lastPathComponent, archive: nil)
        }
    }

    private func loadArchive(_ entry: ProfileAvatarHistoryEntry) {
        begin {
            let data = try await SharedMediaDataLoader.shared.data(for: entry.cropImageURL)
            try await prepare(data, name: entry.description, archive: entry)
        }
    }

    private func chooseGIF(_ gif: GIFSearchResult, page: GIFPickerPage) {
        begin {
            let account = model.accountSession()
            guard model.isCurrentAccountSession(account),
                  let url = DiscordProfileImageAssets.editableGIFURL(gif.previewURL ?? gif.mediaURL),
                  !GIFPickerMediaPolicy.isVideo(url)
            else { throw ChatProviderError.invalidRequest("This GIF does not include an editable image.") }
            let download = Task { try await SharedMediaDataLoader.shared.data(for: url) }
            if page != .favorites {
                let query: String
                if case let .search(value) = page { query = value } else { query = "" }
                // The first-party picker starts the image fetch before its
                // independent selection notification. A notification failure
                // must not reject an otherwise usable image or trigger retry.
                Task { try? await account.provider.recordProfileGIFSelection(id: gif.id, query: query) }
            }
            let data = try await withTaskCancellationHandler { try await download.value } onCancel: { download.cancel() }
            guard model.isCurrentAccountSession(account) else { throw CancellationError() }
            try await prepare(data, name: "selected", archive: nil)
        }
    }

    private func prepare(_ data: Data, name: String, archive: ProfileAvatarHistoryEntry?) async throws {
        let image = try await Task.detached { try ProfileImageSource(data: data) }.value
        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory.appending(path: "profile-image-\(UUID().uuidString)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        temporaryFiles.append(url)
        source = image; sourceURL = url; filename = name; self.archive = archive
    }

    private func process(_ geometry: ProfileImageCropGeometry) {
        guard let source, canApply(source) else { return }
        if let archive, !geometry.hasEdits {
            apply(.history(archive), archive.cropImageURL)
            dismiss?()
            return
        }
        begin {
            let account = model.accountSession()
            let operation = Task.detached { try ProfileImageProcessor.crop(source, geometry: geometry) }
            let output = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
            try Task.checkCancellation()
            guard model.isCurrentAccountSession(account) else { throw CancellationError() }
            let url = FileManager.default.temporaryDirectory.appending(path: "profile-draft-\(UUID().uuidString)")
            try output.data.write(to: url, options: [.atomic, .completeFileProtection])
            let upload = ProfileImageUpload(data: output.data, mediaType: output.mediaType, description: imageDescription(),
                                            originalMD5: source.originalMD5, isAnimated: output.isAnimated)
            apply(.upload(upload), url)
            dismiss?(allowsDisabled: true)
        }
    }

    private func canApply(_ source: ProfileImageSource) -> Bool {
        if purpose == .banner || editor.scope.guildID != nil { return editor.isNitro }
        return !source.isAnimated || editor.isNitro || editor.snapshot?.presentation.user.premiumType == 1
    }

    private func imageDescription() -> String {
        let name = archive.map { $0.description.components(separatedBy: ", added ").first ?? $0.description } ?? filename
        let date = Date().formatted(.dateTime.day().month(.wide).year().hour().minute())
        return "\(name), \(archive == nil ? "added" : "edited") \(date)"
    }

    private func cancelCrop() {
        if isBusy { work?.cancel(); return }
        source = nil; sourceURL = nil; archive = nil; showsGIFs = false
    }

    private func delete(_ entry: ProfileAvatarHistoryEntry) {
        deleteCandidate = nil
        begin { try await editor.deleteHistory(entry) }
    }

    private func begin(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        work = Task {
            defer { isBusy = false }
            do { try await operation() } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct ProfileRecentAvatarButton: View {
    let entry: ProfileAvatarHistoryEntry
    let choose: () -> Void
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: choose) {
            AvatarView(name: "", url: entry.imageURL, size: 56)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button("Remove Avatar", systemImage: "trash.fill", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.mini)
            }
        }
        .onHover { isHovered = $0 }
        .help(entry.description)
        .accessibilityLabel(entry.description)
        .contextMenu { Button("Remove Avatar", systemImage: "trash", role: .destructive, action: remove) }
    }
}
