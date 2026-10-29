import Foundation
import SakuraCordModels

/// Per-file progress of attachment sends, kept out of observation so a byte
/// update repaints only its timeline row.
///
/// Like the first-party composer, a staged file starts uploading as soon as it
/// is attached, and its progress carries over once its message is sent. A
/// send's entry lives from admission until it is confirmed or discarded. A
/// failed send keeps it only when a file never reached storage, which is what
/// marks that message's files as a failed upload.
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
    /// Staged files uploading before Send, by draft attachment ID.
    private var preuploadFractions: [UUID: Double] = [:]
    /// Staged files storage already accepted; their message posts them as they are.
    private var storedPreuploads: Set<UUID> = []

    /// Whether the row of this local send shows upload cards.
    func tracks(nonce: String?) -> Bool {
        nonce.map { uploads[$0] != nil } ?? false
    }

    func fraction(nonce: String?, attachmentID: String) -> Double {
        guard let upload = nonce.flatMap({ uploads[$0] }) else { return 0 }
        return upload.isUploaded ? 1 : upload.fractions[attachmentID] ?? 0
    }

    /// Once storage has every file, the message itself is being posted.
    func canCancel(nonce: String?, attachmentID: String) -> Bool {
        guard let nonce, let upload = uploads[nonce], upload.fractions[attachmentID] != nil else { return false }
        return !upload.isUploaded
    }

    func beginPreupload(_ attachmentID: UUID) {
        preuploadFractions[attachmentID] = 0
    }

    /// A file whose message was already sent keeps that message's progress,
    /// and one dropped from the composer is forgotten.
    func endPreupload(_ attachmentID: UUID, stored: Bool) {
        let wasUploading = preuploadFractions.removeValue(forKey: attachmentID) != nil
        guard stored else {
            storedPreuploads.remove(attachmentID)
            // A sent file whose early upload failed is stored again from the start.
            let id = attachmentID.uuidString
            if let nonce = nonce(sending: id) {
                uploads[nonce]?.fractions[id] = 0
                notify(nonce: nonce, endsCancellation: false)
            }
            return
        }
        if wasUploading { storedPreuploads.insert(attachmentID) }
    }

    /// A send whose files are all stored already posts at once, without upload cards.
    func begin(_ draft: SendMessageDraft) {
        guard draft.voiceMessage == nil, !draft.attachments.isEmpty else { return }
        let ids = draft.attachments.map(\.id)
        defer {
            for id in ids {
                preuploadFractions[id] = nil
                storedPreuploads.remove(id)
            }
        }
        guard !ids.allSatisfy(storedPreuploads.contains) else { return }
        uploads[draft.nonce] = Upload(fractions: Dictionary(uniqueKeysWithValues: ids.map {
            ($0.uuidString, storedPreuploads.contains($0) ? 1 : preuploadFractions[$0] ?? 0)
        }))
    }

    /// Progress leaves the message unchanged, so only these updates notify;
    /// every other change here accompanies a change to the message itself.
    /// A staged file's upload reports without a nonce, also once it is sent.
    func apply(_ progress: MessageSendProgress, nonce: String? = nil) {
        switch progress {
        case let .uploading(fileID?, _, completed, total):
            guard total > 0 else { return }
            let fraction = min(1, Double(completed) / Double(total))
            // Progress arrives on separate hops, so an older report can land late.
            if let current = preuploadFractions[fileID] {
                preuploadFractions[fileID] = max(current, fraction)
                return
            }
            let id = fileID.uuidString
            guard let nonce = nonce ?? self.nonce(sending: id),
                  let current = uploads[nonce]?.fractions[id], fraction > current
            else { return }
            uploads[nonce]?.fractions[id] = fraction
            notify(nonce: nonce, endsCancellation: false)
        case .submitting:
            guard let nonce, uploads[nonce] != nil else { return }
            uploads[nonce]?.isUploaded = true
            notify(nonce: nonce, endsCancellation: true)
        default:
            return
        }
    }

    /// Keeps the entry only when a file never reached storage.
    func fail(nonce: String) {
        if uploads[nonce]?.isUploaded == true { uploads[nonce] = nil }
    }

    func remove(attachmentID: String, nonce: String) {
        uploads[nonce]?.fractions[attachmentID] = nil
    }

    func finish(nonce: String) {
        uploads[nonce] = nil
    }

    func reset() {
        uploads.removeAll()
        preuploadFractions.removeAll()
        storedPreuploads.removeAll()
    }

    private func nonce(sending attachmentID: String) -> String? {
        uploads.first { $0.value.fractions[attachmentID] != nil }?.key
    }

    private func notify(nonce: String, endsCancellation: Bool) {
        NotificationCenter.default.post(
            name: Self.didChange,
            object: self,
            userInfo: [Self.nonceKey: nonce, Self.endsCancellationKey: endsCancellation]
        )
    }

    static let nonceKey = "nonce"
    /// Set when the send's files can no longer be stopped.
    static let endsCancellationKey = "endsCancellation"
}
