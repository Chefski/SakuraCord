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
        for _ in 0 ..< 200 where HeldStorageURLProtocol.heldCount < expectedHeld {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(HeldStorageURLProtocol.heldCount == expectedHeld)
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
            #expect(payload["uploaded_filename"] == .string("kept-upload"))
        }
        // URLSession stops the protocol after it completes the cancelled task.
        for _ in 0 ..< 200 where HeldStorageURLProtocol.stoppedCount < expectedHeld {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(HeldStorageURLProtocol.stoppedCount == expectedHeld)
    }
}

/// Answers the reservation, completes the kept file's storage PUT, and holds
/// the others open until their transfer is cancelled.
private final class HeldStorageURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var holdsEveryUpload = false
        var held = 0
        var stopped = 0
    }

    private static let state = Mutex(State())
    static var heldCount: Int { state.withLock(\.held) }
    static var stoppedCount: Int { state.withLock(\.stopped) }

    static func reset(holdsEveryUpload: Bool) {
        state.withLock { $0 = State(holdsEveryUpload: holdsEveryUpload) }
    }

    private var isHeld = false

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if request.httpMethod == "PUT",
           url.lastPathComponent == "stopped" || Self.state.withLock(\.holdsEveryUpload)
        {
            isHeld = true
            Self.state.withLock { $0.held += 1 }
            return
        }
        let data = request.httpMethod == "POST"
            ? Data(#"""
            {"attachments":[
              {"id":0,"upload_url":"https://upload.example/kept","upload_filename":"kept-upload"},
              {"id":1,"upload_url":"https://upload.example/stopped","upload_filename":"stopped-upload"}
            ]}
            """#.utf8)
            : Data()
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        if isHeld { Self.state.withLock { $0.stopped += 1 } }
    }
}
