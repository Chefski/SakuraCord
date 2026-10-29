@testable import DiscordProtocol
import Foundation
import SakuraCordModels
import Synchronization
import Testing

/// A file the user stops must never reach the message, and stopping every
/// file must not post the message at all.
@Suite(.serialized)
struct UploadCancellationContractTests {
    @Test(arguments: [false, true])
    func stoppedFilesLeaveTheMessage(stopsEveryFile: Bool) async throws {
        HeldStorageURLProtocol.reset(holdsEveryUpload: stopsEveryFile)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ["kept.bin", "stopped.bin"].map { name in
            let url = directory.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return AttachmentUploadFile(url: url, name: name, id: UUID())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldStorageURLProtocol.self]
        let provider = DiscordRESTProvider(
            credentials: TestCredentialStore(), handle: CredentialHandle(accountID: "1"),
            session: URLSession(configuration: configuration)
        )
        let upload = Task {
            try await provider.uploadAttachmentFiles(files, channelID: ChannelID(rawValue: 200), progress: { _ in })
        }
        let expectedHeld = stopsEveryFile ? 2 : 1
        #expect(await eventually { HeldStorageURLProtocol.heldCount == expectedHeld })
        for file in stopsEveryFile ? files : [files[1]] {
            await provider.cancelAttachmentUpload(try #require(file.id))
        }
        if stopsEveryFile {
            await #expect(throws: CancellationError.self) { try await upload.value }
        } else {
            let uploaded = try await upload.value
            #expect(uploaded.count == 1)
            guard case let .object(payload) = uploaded.first else { Issue.record("Missing kept attachment"); return }
            #expect(payload["filename"] == .string("kept.bin"))
            #expect(payload["uploaded_filename"] == .string("slot0/kept.bin"))
        }
        // URLSession stops the protocol after it completes the cancelled task.
        #expect(await eventually { HeldStorageURLProtocol.stoppedCount == expectedHeld })
    }

    /// A file stopped while its message waits for its turn may already be
    /// deleted, so the send must neither read nor reserve it.
    @Test func fileStoppedBeforeItsTurnIsNeverRead() async throws {
        HeldStorageURLProtocol.reset(holdsEveryUpload: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = directory.appendingPathComponent("kept.bin")
        try Data("kept".utf8).write(to: kept)
        let files = [
            AttachmentUploadFile(url: kept, name: "kept.bin", id: UUID()),
            AttachmentUploadFile(url: directory.appendingPathComponent("stopped.bin"), name: "stopped.bin", id: UUID()),
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldStorageURLProtocol.self]
        let provider = DiscordRESTProvider(
            credentials: TestCredentialStore(), handle: CredentialHandle(accountID: "1"),
            session: URLSession(configuration: configuration)
        )
        await provider.cancelAttachmentUpload(try #require(files[1].id))
        let uploaded = try await provider.uploadAttachmentFiles(files, channelID: ChannelID(rawValue: 200), progress: { _ in })
        #expect(HeldStorageURLProtocol.reservedNames == ["kept.bin"])
        guard case let .object(payload) = uploaded.first, uploaded.count == 1 else { Issue.record("Missing kept attachment"); return }
        #expect(payload["uploaded_filename"] == .string("slot0/kept.bin"))
    }

    /// A file stored as it was attached posts as it is rather than uploading
    /// twice, and one removed from the draft is deleted from storage.
    @Test func filesStoredOnAttachPostWithoutUploadingAgain() async throws {
        HeldStorageURLProtocol.reset(holdsEveryUpload: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let attachments = try ["kept.bin", "removed.bin"].map { name in
            let url = directory.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return ForumPostAttachment(url: url)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldStorageURLProtocol.self]
        let provider = DiscordRESTProvider(
            credentials: TestCredentialStore(), handle: CredentialHandle(accountID: "1"),
            session: URLSession(configuration: configuration)
        )
        let channelID = ChannelID(rawValue: 200)
        for attachment in attachments {
            #expect(await provider.preuploadAttachment(attachment, channelID: channelID, progress: { _ in }))
        }
        await provider.discardPreuploadedAttachment(attachments[1].id)
        #expect(HeldStorageURLProtocol.requests.last == "DELETE /api/v9/attachments/slot0%2Fremoved.bin")
        let requestCount = HeldStorageURLProtocol.requests.count
        let uploaded = try await provider.uploadForumAttachments([attachments[0]], channelID: channelID, progress: { _ in })
        #expect(HeldStorageURLProtocol.requests.count == requestCount)
        guard case let .object(payload) = uploaded.first, uploaded.count == 1 else { Issue.record("Missing kept attachment"); return }
        #expect(payload["uploaded_filename"] == .string("slot0/kept.bin"))
    }
}

/// Answers the reservation, completes the kept file's storage PUT, and holds
/// the others open until their transfer is cancelled.
private final class HeldStorageURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var holdsEveryUpload = false
        var held = 0
        var stopped = 0
        var reservedNames: [String] = []
        var requests: [String] = []
    }

    private static let state = Mutex(State())
    static var heldCount: Int { state.withLock(\.held) }
    static var stoppedCount: Int { state.withLock(\.stopped) }
    static var reservedNames: [String] { state.withLock(\.reservedNames) }
    static var requests: [String] { state.withLock(\.requests) }

    static func reset(holdsEveryUpload: Bool) {
        state.withLock { $0 = State(holdsEveryUpload: holdsEveryUpload) }
    }

    private var isHeld = false

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        Self.state.withLock { $0.requests.append("\(request.httpMethod ?? "GET") \(path)") }
        if request.httpMethod == "PUT",
           url.lastPathComponent == "stopped" || Self.state.withLock(\.holdsEveryUpload)
        {
            isHeld = true
            Self.state.withLock { $0.held += 1 }
            return
        }
        var data = Data()
        if request.httpMethod == "POST" {
            let names = Self.reservedFilenames(in: request)
            Self.state.withLock { $0.reservedNames = names }
            let slots = names.enumerated().map { index, name in
                let stem = (name as NSString).deletingPathExtension
                return ["id": index, "upload_url": "https://upload.example/\(stem)", "upload_filename": "slot\(index)/\(name)"] as [String: Any]
            }
            data = (try? JSONSerialization.data(withJSONObject: ["attachments": slots])) ?? Data()
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func reservedFilenames(in request: URLRequest) -> [String] {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
        }
        let files = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["files"] as? [[String: Any]]
        return files?.compactMap { $0["filename"] as? String } ?? []
    }

    override func stopLoading() {
        if isHeld { Self.state.withLock { $0.stopped += 1 } }
    }
}
