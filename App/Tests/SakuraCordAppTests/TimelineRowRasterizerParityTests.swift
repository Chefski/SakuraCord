import AppKit
@testable import SakuraCord
import SakuraCordModels
import Testing

/// The motion presenter shows rows the raster worker paints off the main
/// thread. They must be the canvas's pixels exactly, also while the main
/// thread paints at the same time: Core Graphics bleeds colour between
/// contexts two threads paint at once unless `NativeTimelinePaintLock`
/// keeps them apart.
@MainActor
@Test
func `raster worker paints timeline rows exactly as the main thread does`() async throws {
    let appearance = try #require(NSAppearance(named: .darkAqua))
    let items = parityItems()
    let widths: [CGFloat] = [560, 437]
    var references: [NativeTimelineRowRasterizer.Key: [UInt8]] = [:]
    var jobs: [NativeTimelineRowRasterizer.Job] = []
    for width in widths {
        for item in items {
            let layout = NativeTimelineRowLayout.make(item: item, width: width)
            let image = try #require(mainThreadPaint(item, layout: layout, width: width, appearance: appearance))
            let key = NativeTimelineRowRasterizer.Key(identifier: item.identifier, pixelWidth: Int(width * 2))
            references[key] = pixels(of: image)
            jobs.append(.init(
                key: key, item: item, layout: layout, width: width, scale: 2, appearance: appearance,
                context: nil, model: nil, spoilerRevealStore: NativeTimelineSpoilerRevealStore(),
                animatedReactionIDs: [], displayColorSpace: CGColorSpaceCreateDeviceRGB()
            ))
        }
    }

    let rasterizer = NativeTimelineRowRasterizer()
    var bitmaps: [NativeTimelineRowRasterizer.Bitmap] = []
    for _ in 0 ..< 2 {
        rasterizer.submit(jobs)
        // Main paints rows while the worker paints, as the canvas may, a
        // row at a time so other main-actor work keeps running.
        let deadline = ContinuousClock.now + .seconds(10)
        var next = 0
        while !rasterizer.isIdle, ContinuousClock.now < deadline {
            let item = items[next % items.count]
            next += 1
            _ = mainThreadPaint(
                item, layout: NativeTimelineRowLayout.make(item: item, width: 500), width: 500, appearance: appearance
            )
            try await Task.sleep(for: .milliseconds(5))
        }
        bitmaps += rasterizer.takeFinished()
    }

    #expect(bitmaps.count == jobs.count * 2)
    for bitmap in bitmaps {
        let actual = pixels(of: bitmap.deviceImage)
        let expected = references[bitmap.key] ?? []
        let first = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        #expect(
            actual == expected,
            "row \(bitmap.key) sizes \(actual.count)/\(expected.count) first difference at byte \(first ?? -1) of row width \(bitmap.deviceImage.width)"
        )
    }
}

@MainActor
private func mainThreadPaint(
    _ item: NativeMessageTimelineItem, layout: NativeTimelineRowLayout, width: CGFloat, appearance: NSAppearance
) -> CGImage? {
    NativeTimelineRowPainter.rasterizeForDisplay(
        width: width, height: layout.height, scale: 2, colorSpace: CGColorSpaceCreateDeviceRGB()
    ) {
        appearance.performAsCurrentDrawingAppearance {
            NativeTimelineRowPainter.draw(
                item: item, layout: layout, in: CGRect(x: 0, y: 0, width: width, height: layout.height),
                model: nil, isHovered: false, spoilerRevealStore: NativeTimelineSpoilerRevealStore()
            )
        }
    }
}

private func pixels(of image: CGImage) -> [UInt8] {
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
    var result: [UInt8] = []
    for row in 0 ..< image.height {
        result.append(contentsOf: UnsafeBufferPointer(start: bytes + row * image.bytesPerRow, count: image.width * 4))
    }
    return result
}

@MainActor
private func parityItems() -> [NativeMessageTimelineItem] {
    let author = User(id: UserID(rawValue: 9_100), username: "parity.fixture", displayName: "Parity Fixture")
    let channelID = ChannelID(rawValue: 9_101)
    let messages = [
        Message(id: MessageID(rawValue: 9_110), channelID: channelID, author: author, content: "Hello from the timeline"),
        Message(
            id: MessageID(rawValue: 9_111), channelID: channelID, author: author,
            content: String(
                repeating: "A **long** message that wraps across several lines, with a link to https://example.com and `code`. ",
                count: 4
            )
        ),
        Message(
            id: MessageID(rawValue: 9_112), channelID: channelID, author: author, content: "Reactions",
            reactions: [
                Reaction(emoji: "👍", count: 3, didCurrentUserReact: true),
                Reaction(emoji: "🎉", count: 1),
            ]
        ),
        Message(
            id: MessageID(rawValue: 9_113), channelID: channelID, author: author, content: "",
            embeds: [
                MessageEmbed(
                    title: "Embed title", description: "An embed with an accent rail and fields.",
                    color: 0x55DDFF,
                    fields: [MessageEmbedField(name: "Field", value: "Value", isInline: true)]
                ),
            ]
        ),
    ]
    return messages.map { message in
        .message(
            MessageRowPresentation(
                message: message, startsGroup: true, startsDay: false, replyPreview: nil, isReplyAvailable: false
            ),
            isUnreadBoundary: false,
            isHighlighted: false
        )
    }
}
