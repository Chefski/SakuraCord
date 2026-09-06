import MediaPipeline
import SakuraCordModels
import SwiftUI
import UniformTypeIdentifiers

struct ProfileWidgetEditableImage: View {
    let image: ProfileWidgetImage?
    let purpose: ProfileImagePurpose
    let animates: Bool
    let editor: ProfileEditorState?
    let aspectRatio: Double
    let update: (ProfileWidgetImage?) -> Void
    @State private var importing = false
    @State private var cropping = false
    @State private var source: ProfileImageSource?
    @State private var sourceURL: URL?
    @State private var filename = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var work: Task<Void, Never>?
    @State private var temporaryFiles: [URL] = []
    @State private var lastEdit: ProfileWidgetImageEdit?
    @State private var initialGeometry: ProfileImageCropGeometry?

    var body: some View {
        ZStack {
            ProfileWidgetImageView(url: image?.url, animates: animates, contentMode: .fill)
            if let editor, editor.canEditWidgets, image == nil {
                Button { importing = true } label: { Image(systemName: "photo.badge.plus").font(.system(size: 20)).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    .buttonStyle(.plain).accessibilityLabel("Upload Image")
            }
            if busy { ProgressView().controlSize(.small) }
        }
        .overlay(alignment: .topTrailing) {
            if editor?.canEditWidgets == true, image != nil {
                Menu {
                    Button("Change Image") { importing = true }
                    if let lastEdit, image?.reference == lastEdit.reference {
                        Button("Edit Image") {
                            source = lastEdit.source; sourceURL = lastEdit.url; filename = lastEdit.filename
                            initialGeometry = lastEdit.geometry; cropping = true
                        }
                    }
                    Button("Remove Image", role: .destructive) { work?.cancel(); update(nil) }
                } label: { Image(systemName: "pencil").padding(6) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .background(.regularMaterial, in: .circle).padding(4).accessibilityLabel("Change Image")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: ["jpg", "jpeg", "jfif", "png", "gif", "webp", "avif"].compactMap { UTType(filenameExtension: $0) }) { result in
            switch result {
            case let .success(url): load(url)
            case let .failure(error): errorMessage = error.localizedDescription
            }
        }
        .profileEditorOverlay(isPresented: $cropping) {
            if let source, let sourceURL {
                ProfileImageCropView(image: source, imageURL: sourceURL, filename: filename, purpose: purpose,
                                     isProcessing: busy, canApply: editor?.canEditWidgets == true, aspectRatio: aspectRatio, initialGeometry: initialGeometry,
                                     cancel: { work?.cancel(); cropping = false }, apply: crop)
                    .profileEditorDismissDisabled(busy)
            }
        }
        .alert("Unable to Use Image", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onDisappear {
            work?.cancel()
            for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func load(_ url: URL) {
        work?.cancel()
        work = Task {
            busy = true
            defer { busy = false }
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                let decoded = try await Task.detached { try ProfileImageSource(data: data) }.value
                try Task.checkCancellation()
                let local = FileManager.default.temporaryDirectory.appending(path: "profile-widget-source-\(UUID().uuidString)")
                try data.write(to: local, options: [.atomic, .completeFileProtection])
                temporaryFiles.append(local)
                source = decoded; sourceURL = local; filename = url.lastPathComponent; initialGeometry = nil; cropping = true
            } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        }
    }

    private func crop(_ geometry: ProfileImageCropGeometry) {
        guard let source, let editor, editor.canEditWidgets, !busy else { return }
        let generation = editor.draftGeneration
        work = Task {
            busy = true
            defer { busy = false }
            var outputURL: URL?
            do {
                let processing = Task.detached { try ProfileImageProcessor.crop(source, geometry: geometry) }
                let output = try await withTaskCancellationHandler { try await processing.value } onCancel: { processing.cancel() }
                try Task.checkCancellation()
                guard generation == editor.draftGeneration else { throw CancellationError() }
                guard output.data.count <= 10 * 1024 * 1024 else { throw ProfileWidgetImageError.tooLarge }
                let local = FileManager.default.temporaryDirectory.appending(path: "profile-widget-draft-\(UUID().uuidString)")
                outputURL = local
                try output.data.write(to: local, options: [.atomic, .completeFileProtection])
                let base = URL(filePath: filename).deletingPathExtension().lastPathComponent
                let ext = UTType(mimeType: output.mediaType)?.preferredFilenameExtension ?? "png"
                let uploaded = try await editor.uploadWidgetImage(fileURL: local, filename: "\(base.isEmpty ? "image" : base).\(ext)", contentType: output.mediaType)
                outputURL = nil // The editor owns the successful draft preview.
                try Task.checkCancellation()
                if let sourceURL {
                    lastEdit = ProfileWidgetImageEdit(source: source, url: sourceURL, filename: filename, geometry: geometry, reference: uploaded.reference)
                }
                update(uploaded); cropping = false
            } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
            if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        }
    }
}

private struct ProfileWidgetImageEdit {
    let source: ProfileImageSource
    let url: URL
    let filename: String
    let geometry: ProfileImageCropGeometry
    let reference: ProfileWidgetImage.Reference
}

private enum ProfileWidgetImageError: LocalizedError {
    case tooLarge
    var errorDescription: String? { String(localized: "The edited image must be 10 MB or smaller.", bundle: #bundle) }
}
