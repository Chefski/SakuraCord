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
    var isCoverHovered = false
    var onHoverChange: ((Bool) -> Void)?
    var removeImage: (() -> Void)?
    let update: (ProfileWidgetImage?) -> Void
    @State private var isHovered = false
    @State private var isActionHovered = false
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

    private var isActive: Bool {
        purpose == .widgetCover ? isCoverHovered : isHovered || isActionHovered
    }

    var body: some View {
        ZStack {
            ProfileWidgetImageView(url: image?.url, animates: animates, contentMode: .fill)
            if let editor, editor.canEditPersonalWidget, image == nil {
                Button { importing = true } label: { Image(systemName: "photo.badge.plus").font(.system(size: 20))
                    .frame(width: 24, height: 24)
                    .nativeHoverPopover(isPresented: .constant(isActive)) {
                        Text("Upload Image", bundle: #bundle).font(.subheadline.weight(.medium))
                            .fixedSize().padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: purpose == .widgetCover ? .topLeading : .center)
                    .padding(purpose == .widgetCover ? 16 : 0)
                    .contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Upload Image")
            } else if editor?.canEditPersonalWidget == true, purpose == .widgetField {
                Button { importing = true } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Change Image")
            }
            if busy { ProgressView().controlSize(.small) }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(isActive && editor?.canEditPersonalWidget == true ? 0.07 : 0))
                .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if editor?.canEditPersonalWidget == true, image != nil || removeImage != nil {
                HoverActionPill {
                    if image != nil, purpose == .widgetCover {
                        Menu {
                            Button("Change Image") { importing = true }
                            if let lastEdit, image?.reference == lastEdit.reference {
                                Button("Edit Image") {
                                    source = lastEdit.source; sourceURL = lastEdit.url; filename = lastEdit.filename
                                    initialGeometry = lastEdit.geometry; cropping = true
                                }
                            }
                            Button("Remove Image", role: .destructive) { remove() }
                        } label: {
                            HoverActionControlLabel { Image(systemName: "pencil").font(.callout.weight(.medium)) }
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Change Image")
                        .help("Change Image")
                    } else if removeImage != nil {
                        HoverActionButton(systemImage: "trash", help: String(localized: "Remove Image", bundle: #bundle), role: .destructive, action: remove)
                    }
                }
                .onModalHover { isActionHovered = $0 }
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
                .accessibilityHidden(!isActive)
                .padding(.trailing, purpose == .widgetCover ? 48 : 0)
                .padding(.top, purpose == .widgetCover ? 8 : 0)
                .offset(x: purpose == .widgetCover ? 0 : 8, y: purpose == .widgetCover ? 0 : -8)
            }
        }
        .onModalHover { isHovered = $0 }
        .onChange(of: isActive) { _, active in onHoverChange?(active) }
        .onDisappear { onHoverChange?(false) }
        .contextMenu {
            if editor?.canEditPersonalWidget == true {
                Button(image == nil ? "Upload Image" : "Change Image") { importing = true }
                if let lastEdit, image?.reference == lastEdit.reference {
                    Button("Edit Image") {
                        source = lastEdit.source; sourceURL = lastEdit.url; filename = lastEdit.filename
                        initialGeometry = lastEdit.geometry; cropping = true
                    }
                }
                if image != nil || removeImage != nil { Button("Remove Image", role: .destructive, action: remove) }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: ["jpg", "jpeg", "jfif", "png", "gif", "webp", "avif"].compactMap { UTType(filenameExtension: $0) }) { result in
            switch result {
            case let .success(url): load(url)
            case let .failure(error): errorMessage = error.localizedDescription
            }
        }
        .windowModal(isPresented: $cropping) {
            if let source, let sourceURL {
                ProfileImageCropView(image: source, imageURL: sourceURL, filename: filename, purpose: purpose,
                                     isProcessing: busy, canApply: editor?.canEditPersonalWidget == true, aspectRatio: aspectRatio, initialGeometry: initialGeometry,
                                     cancel: { work?.cancel(); cropping = false }, apply: crop)
                    .windowModalDismissDisabled(busy)
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

    private func remove() {
        work?.cancel()
        if let removeImage { removeImage() } else { update(nil) }
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
        guard let source, let editor, editor.canEditPersonalWidget, !busy else { return }
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
