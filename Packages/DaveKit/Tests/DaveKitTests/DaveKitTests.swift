@testable import DaveKit
import DaveKitTestSupport
import Foundation
import Testing

private actor TestDelegate: DaveSessionDelegate {
    private(set) var keyPackageCount = 0
    private(set) var lastKeyPackage = Data()
    private(set) var readyTransitionIDs: [UInt16] = []

    func mlsKeyPackage(keyPackage: Data) async {
        keyPackageCount += 1
        lastKeyPackage = keyPackage
    }

    func readyForTransition(transitionId: UInt16) async {
        readyTransitionIDs.append(transitionId)
    }

    func mlsCommitWelcome(welcome: Data) async {}
    func mlsInvalidCommitWelcome(transitionId: UInt16) async {}
}

@Test func `prepare epoch distinguishes new group from protocol version rotation`() async {
    let delegate = TestDelegate()
    let manager = DaveSessionManager(selfUserId: "1", groupId: 10, delegate: delegate)

    await manager.prepareEpoch(transitionId: 3, epoch: "1", protocolVersion: 1)
    #expect(await delegate.keyPackageCount == 1)
    #expect(await !delegate.lastKeyPackage.isEmpty)
    #expect(await delegate.readyTransitionIDs.isEmpty)

    await manager.prepareEpoch(transitionId: 44, epoch: "2", protocolVersion: 2)
    #expect(await delegate.keyPackageCount == 1)
    #expect(await delegate.readyTransitionIDs == [44])
}

@Test func `passthrough encryption round trips H 264 frames`() async throws {
    let delegate = TestDelegate()
    let manager = DaveSessionManager(selfUserId: "1", groupId: 10, delegate: delegate)
    await manager.addUser(userId: "2")
    await manager.assignVideoSSRC(43, codec: .h264)
    let frame = Data([0, 0, 0, 1, 0x67, 1, 2, 3, 0, 0, 0, 1, 0x65, 4, 5, 6])

    let encrypted = try await manager.encrypt(ssrc: 43, data: frame, mediaType: .video)
    let decrypted = try await manager.decrypt(userId: "2", data: encrypted, mediaType: .video)

    #expect(encrypted == frame)
    #expect(decrypted == frame)
}

@Test func `passthrough encryption round trips audio frames`() async throws {
    let delegate = TestDelegate()
    let manager = DaveSessionManager(selfUserId: "1", groupId: 10, delegate: delegate)
    await manager.addUser(userId: "2")
    await manager.assignAudioSSRC(42)
    let frame = Data([0xF8, 0xFF, 0xFE])

    let encrypted = try await manager.encrypt(ssrc: 42, data: frame)
    let decrypted = try await manager.decrypt(userId: "2", data: encrypted)

    #expect(DaveSessionManager.maxSupportedProtocolVersion() >= 1)
    #expect(encrypted == frame)
    #expect(decrypted == frame)
}

@Test func `reinstalling a ratchet preserves nonces and replay protection`() throws {
    let encryptor = Encryptor()
    let decryptor = Decryptor()
    let ratchet = KeyRatchet(handle: makeTestKeyRatchet(1))
    encryptor.assign(ssrc: 42, codec: .opus)
    encryptor.setKeyRatchet(keyRatchet: ratchet)
    decryptor.transitionToKeyRatchet(keyRatchet: ratchet)
    let frame = Data([0xF8, 0xFF, 0xFE])
    let first = try encryptor.encrypt(ssrc: 42, data: frame)
    #expect(try decryptor.decrypt(data: first) == frame)

    let sameEpoch = KeyRatchet(handle: makeTestKeyRatchet(1))
    encryptor.setKeyRatchet(keyRatchet: sameEpoch)
    decryptor.transitionToKeyRatchet(keyRatchet: sameEpoch)
    let second = try encryptor.encrypt(ssrc: 42, data: frame)
    #expect(first != second)
    #expect(try decryptor.decrypt(data: second) == frame)
    #expect(throws: DecryptError.self) { try decryptor.decrypt(data: first) }

    let nextEpoch = KeyRatchet(handle: makeTestKeyRatchet(2))
    encryptor.setKeyRatchet(keyRatchet: nextEpoch)
    decryptor.transitionToKeyRatchet(keyRatchet: nextEpoch)
    let third = try encryptor.encrypt(ssrc: 42, data: frame)
    #expect(third != first && third != second)
    #expect(try decryptor.decrypt(data: third) == frame)
}

@Test func `fresh voice sessions discard participants and pending transitions`() async throws {
    let delegate = TestDelegate()
    let manager = DaveSessionManager(selfUserId: "1", groupId: 10, delegate: delegate)
    await manager.addUser(userId: "2")
    await manager.prepareTransition(transitionId: 7, protocolVersion: 0)
    await manager.resetForFreshSession()
    await manager.executeTransition(transitionId: 7)
    let frame = Data([0xF8, 0xFF, 0xFE])
    #expect(try await manager.decrypt(userId: "2", data: frame) == nil)
    await #expect(throws: EncryptError.missingKeyRatchet) {
        try await manager.encrypt(ssrc: 42, data: frame)
    }
}

@Test func `invalid welcome regenerates the group and discards pending transitions`() async throws {
    let delegate = TestDelegate()
    let manager = DaveSessionManager(selfUserId: "1", groupId: 10, delegate: delegate)
    await manager.resetForFreshSession()
    await manager.selectProtocol(protocolVersion: 1)
    let firstKeyPackage = await delegate.lastKeyPackage
    await manager.prepareTransition(transitionId: 7, protocolVersion: 0)
    await manager.mlsWelcome(transitionId: 8, welcome: Data([0]))
    #expect(await delegate.keyPackageCount == 2)
    #expect(await delegate.lastKeyPackage != firstKeyPackage)
    await manager.executeTransition(transitionId: 7)
    await #expect(throws: EncryptError.missingKeyRatchet) {
        try await manager.encrypt(ssrc: 42, data: Data([0xF8, 0xFF, 0xFE]))
    }
}
