import Foundation
import SakuraCordModels

/// Per-file progress of the outbox's attachment sends, kept out of
/// observation so a byte update repaints only its timeline row.
///
/// A send's entry lives from admission until it is confirmed or discarded.
/// A failed send keeps it only when a file never reached storage, which is
/// what marks that message's files as a failed upload.
@MainActor
final class AttachmentUploadProgressStore {
    static let didChange = Notification.Name("AttachmentUploadProgressStore.didChange")

    private struct Upload {
        /// Keyed by the draft attachment's ID, which the optimistic row's
        /// attachments share.
        var fractions: [String: Double]
        /// Storage accepted every file. Sent bytes alone do not prove that.
        var isUploaded = false
    }

    private var uploads: [String: Upload] = [:]

    /// Whether the row of this local send shows upload cards.
    func tracks(nonce: String?) -> Bool {
        nonce.map { uploads[$0] != nil } ?? false
    }

    func fraction(nonce: String?, attachmentID: String) -> Double {
        nonce.flatMap { uploads[$0]?.fractions[attachmentID] } ?? 0
    }

    /// Once storage has every file, the message itself is being posted.
    func canCancel(nonce: String?, attachmentID: String) -> Bool {
        guard let nonce, let upload = uploads[nonce], upload.fractions[attachmentID] != nil else { return false }
        return !upload.isUploaded
    }

    func begin(_ draft: SendMessageDraft) {
        guard draft.voiceMessage == nil, !draft.attachments.isEmpty else { return }
        uploads[draft.nonce] = Upload(fractions: Dictionary(
            uniqueKeysWithValues: draft.attachments.map { ($0.id.uuidString, 0) }
        ))
        notify()
    }

    func apply(_ progress: MessageSendProgress, to draft: SendMessageDraft) {
        guard var upload = uploads[draft.nonce] else { return }
        switch progress {
        case let .uploading(fileIndex, _, completed, total):
            guard draft.attachments.indices.contains(fileIndex), total > 0 else { return }
            let id = draft.attachments[fileIndex].id.uuidString
            // Progress arrives on separate hops, so an older report can land late.
            guard let current = upload.fractions[id] else { return }
            upload.fractions[id] = max(current, min(1, Double(completed) / Double(total)))
        case .submitting:
            for id in upload.fractions.keys { upload.fractions[id] = 1 }
            upload.isUploaded = true
        default:
            return
        }
        uploads[draft.nonce] = upload
        notify()
    }

    /// Keeps the entry only when a file never reached storage.
    func fail(nonce: String) {
        guard uploads[nonce]?.isUploaded == true else { return }
        uploads[nonce] = nil
        notify()
    }

    func remove(attachmentID: String, nonce: String) {
        uploads[nonce]?.fractions[attachmentID] = nil
        notify()
    }

    func finish(nonce: String) {
        guard uploads.removeValue(forKey: nonce) != nil else { return }
        notify()
    }

    func reset() {
        uploads.removeAll()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
