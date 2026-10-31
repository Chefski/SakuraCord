@testable import SakuraCord
import AppKit
import Testing

@MainActor
@Test func `server icon retries a failed load without a view update`() async throws {
    let view = StaticRemoteImageView()
    let image = try makeServerIconFixture()
    var attempts = 0
    var waits: [Duration] = []
    let coordinator = StaticRemoteImage.Coordinator(
        retryDelays: [.seconds(1), .seconds(2)],
        loadImage: { _ in
            attempts += 1
            return attempts == 3 ? image : nil
        },
        wait: { waits.append($0) }
    )
    let request = StaticRemoteImage.RequestIdentity(
        url: try #require(URL(string: "https://cdn.example/retry-server.png")),
        maximumPixelDimension: 88,
        retriesFailedLoads: true
    )
    coordinator.load(request, into: view)
    await coordinator.waitForLoadForTesting()
    #expect(attempts == 3)
    #expect(waits == [.seconds(1), .seconds(2)])
    #expect(view.layer?.contents != nil)
    coordinator.load(request, into: view)
    await coordinator.waitForLoadForTesting()
    #expect(attempts == 3)
    coordinator.cancel()
}

@MainActor
@Test func `server icon retry budget stays bounded across redraws`() async throws {
    let view = StaticRemoteImageView()
    var attempts = 0
    let coordinator = StaticRemoteImage.Coordinator(
        retryDelays: [.seconds(1), .seconds(2)],
        loadImage: { _ in attempts += 1; return nil },
        wait: { _ in }
    )
    let request = StaticRemoteImage.RequestIdentity(
        url: try #require(URL(string: "https://cdn.example/unavailable-server.png")),
        maximumPixelDimension: 88,
        retriesFailedLoads: true
    )
    coordinator.load(request, into: view)
    await coordinator.waitForLoadForTesting()
    coordinator.load(request, into: view)
    await coordinator.waitForLoadForTesting()
    #expect(attempts == 3)
    #expect(view.layer?.contents == nil)
    coordinator.cancel()
    coordinator.load(request, into: view)
    await coordinator.waitForLoadForTesting()
    #expect(attempts == 6)
    coordinator.cancel()
}

@MainActor
@Test(arguments: [false, true])
func `server icon cancellation prevents a stale retry`(replacesRequest: Bool) async throws {
    let view = StaticRemoteImageView()
    let image = try makeServerIconFixture()
    var attempts = 0
    var suspendedWait: CheckedContinuation<Void, Never>?
    let oldURL = try #require(URL(string: "https://cdn.example/old-server.png"))
    let coordinator = StaticRemoteImage.Coordinator(
        retryDelays: [.seconds(1)],
        loadImage: { request in
            attempts += 1
            return request.url == oldURL ? nil : image
        },
        wait: { _ in
            await withCheckedContinuation { suspendedWait = $0 }
        }
    )
    coordinator.load(.init(url: oldURL, maximumPixelDimension: 88, retriesFailedLoads: true), into: view)
    #expect(await eventually { suspendedWait != nil })
    let oldCompletion = try #require(coordinator.loadTaskForTesting)
    if replacesRequest {
        let newURL = try #require(URL(string: "https://cdn.example/new-server.png"))
        coordinator.load(.init(url: newURL, maximumPixelDimension: 88, retriesFailedLoads: true), into: view)
        await coordinator.waitForLoadForTesting()
    } else {
        coordinator.cancel()
    }
    suspendedWait?.resume()
    await oldCompletion.value
    #expect(attempts == (replacesRequest ? 2 : 1))
    #expect((view.layer?.contents != nil) == replacesRequest)
    coordinator.cancel()
}

@MainActor
private func makeServerIconFixture() throws -> CGImage {
    let context = try #require(CGContext(
        data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    return try #require(context.makeImage())
}
