import AppKit
import CryptoKit
import Foundation
import MediaPipeline
import SakuraCordModels

@MainActor
final class UploadPrivacyPreparation {
    struct CheckedFile {
        let url: URL
        let uploadSize: Int64?
    }

    private let store: PrivacySafetySettingsStore
    private let confirm: @MainActor (URL) async -> Bool
    private var generation: UInt64 = 0
    private var approvedOriginals: [URL: Data] = [:]

    init(store: PrivacySafetySettingsStore, confirm: @escaping @MainActor (URL) async -> Bool = UploadPrivacyPreparation.showWarning) {
        self.store = store
        self.confirm = confirm
    }

    func reset() {
        generation &+= 1
        approvedOriginals.removeAll()
    }

    func checkSelection(_ urls: [URL]) async throws -> [CheckedFile] {
        let generation = generation
        for url in urls { approvedOriginals.removeValue(forKey: url.standardizedFileURL) }
        var accepted: [CheckedFile] = []
        for url in urls {
            guard generation == self.generation else { break }
            do {
                accepted.append(try await checkFile(url))
            } catch is CancellationError {
                // Cancel applies only to this file; remaining selections still get checked.
                if Task.isCancelled { break }
            } catch {
                throw error
            }
        }
        return accepted
    }

    func checkFile(_ source: URL) async throws -> CheckedFile {
        let prepared = try await prepare(source)
        defer { prepared.discard() }
        try Task.checkCancellation()
        let accessed = prepared.url.startAccessingSecurityScopedResource()
        defer { if accessed { prepared.url.stopAccessingSecurityScopedResource() } }
        let values = try? prepared.url.resourceValues(forKeys: [.fileSizeKey])
        return CheckedFile(url: source, uploadSize: values?.fileSize.map(Int64.init))
    }

    func prepare(_ source: URL) async throws -> PreparedUploadFile {
        guard store.load().removesMediaMetadata else { return PreparedUploadFile(url: source) }
        let generation = generation
        do {
            return try await UploadMetadataRemover.prepare(source)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Consent covers a stable copy of these exact bytes, never a path alone.
            let copy = try await Self.copyOriginal(source)
            do {
                let digest = try await Self.digest(copy.url)
                let key = source.standardizedFileURL
                if approvedOriginals[key] != digest {
                    guard await confirm(source) else { throw CancellationError() }
                    try Task.checkCancellation()
                    guard generation == self.generation else { throw CancellationError() }
                    approvedOriginals[key] = digest
                }
                guard generation == self.generation else { throw CancellationError() }
                return copy
            } catch {
                copy.discard()
                throw error
            }
        }
    }

    @concurrent
    private static func copyOriginal(_ source: URL) async throws -> PreparedUploadFile {
        try Task.checkCancellation()
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SakuraCord-ApprovedUpload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: output)
            try Task.checkCancellation()
            return PreparedUploadFile(url: output, temporaryDirectory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    @concurrent
    private static func digest(_ source: URL) async throws -> Data {
        try Task.checkCancellation()
        return Data(SHA256.hash(data: try Data(contentsOf: source, options: .mappedIfSafe)))
    }

    private static func showWarning(_ source: URL) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Attach Without Removing Metadata?", bundle: #bundle)
        alert.informativeText = String(
            localized: "Metadata couldn’t be removed from \(source.lastPathComponent). Attaching it anyway may share its location and other personal information.",
            bundle: #bundle
        )
        alert.addButton(withTitle: String(localized: "Attach Anyway", bundle: #bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: #bundle))
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        if let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            let window = keyWindow.sheetParent ?? keyWindow
            return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
