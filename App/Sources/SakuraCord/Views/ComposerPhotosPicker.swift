import CoreTransferable
import PhotosUI
import SakuraCordModels
import SwiftUI
import UniformTypeIdentifiers

struct ComposerPhotosPicker: ViewModifier {
    let model: AppModel
    let destination: MessageComposerDestination
    @Binding var isPresented: Bool
    @State private var selection: [PhotosPickerItem] = []
    @State private var channelID: ChannelID?
    @State private var accountGeneration: UInt64?
    @State private var importToken: UUID?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if importToken != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing photos…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, ChatChromeMetrics.composerWindowInset + 8)
            }
            content
        }
            .photosPicker(
                isPresented: $isPresented,
                selection: $selection,
                maxSelectionCount: max(
                    1,
                    SendMessageDraft.maximumAttachmentCount
                        - model.composerAttachments(for: destination).count
                ),
                selectionBehavior: .ordered,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current
            )
            .onChange(of: isPresented) { _, presented in
                guard presented else { return }
                selection = []
                channelID = model.composerSendChannelID(in: destination)
                accountGeneration = model.accountSessionGeneration
            }
            .task(id: selection) {
                await importSelection()
            }
    }

    private var canImport: Bool {
        !Task.isCancelled
            && channelID != nil
            && channelID == model.composerSendChannelID(in: destination)
            && accountGeneration == model.accountSessionGeneration
            && model.isComposerDropEligible(destination)
    }

    private func importSelection() async {
        guard !selection.isEmpty, canImport else { return }
        let token = UUID()
        importToken = token
        defer {
            if importToken == token { importToken = nil }
        }
        for item in selection {
            guard canImport else { return }
            do {
                guard let file = try await item.loadTransferable(type: ComposerPhotoFile.self) else {
                    throw CocoaError(.fileReadUnknown)
                }
                let batch = ComposerPromisedFileBatch(directory: file.directory, urls: [file.url])
                guard canImport else {
                    batch.discard()
                    return
                }
                await model.addPromisedComposerAttachments(batch, to: destination)
            } catch {
                guard canImport else { return }
                model.errorMessage = String(localized: "Couldn’t load a selection from Photos. Please try again.", bundle: #bundle)
            }
        }
    }
}

/// Prepares the picker’s temporary file before its transfer access expires.
private nonisolated struct ComposerPhotoFile: Transferable {
    let directory: URL
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try await importFile(received)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try await importFile(received)
        }
    }

    @concurrent
    private static func importFile(_ received: ReceivedTransferredFile) async throws -> Self {
        let directory = try await MainActor.run {
            try ComposerPromisedFileStorage.makeReceivingDirectory()
        }
        do {
            let url = directory.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: url)
            try Task.checkCancellation()
            return Self(directory: directory, url: url)
        } catch {
            await MainActor.run {
                ComposerPromisedFileStorage.removeDirectory(directory)
            }
            throw error
        }
    }
}
