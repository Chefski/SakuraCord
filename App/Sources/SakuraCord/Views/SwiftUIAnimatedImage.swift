import QuartzCore
import SwiftUI

/// Uses the shared decoded frames and playback clock while remaining entirely
/// in SwiftUI's display list, which native drag previews can snapshot correctly.
struct SwiftUIAnimatedImage: View {
    let image: DecodedAnimatedImage
    let animates: Bool
    let isLooping: Bool
    let contentMode: ContentMode
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = true
    @State private var startedAt = CACurrentMediaTime()
    @State private var clock = AnimatedImagePlaybackClock()

    private var plays: Bool { animates && isVisible && scenePhase != .background && image.frames.count > 1 }

    var body: some View {
        if image.frames.count == 1, let frame = image.frames.first {
            Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: contentMode)
        } else {
            TimelineView(.animation(minimumInterval: image.frameDurations.min(), paused: !plays)) { _ in
                let elapsed = max(0, (clock.pausedAt ?? CACurrentMediaTime()) - clock.pausedDuration - startedAt)
                if let frame = frame(at: elapsed) {
                    Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: contentMode)
                }
            }
            .onChange(of: plays, initial: true) { _, playing in clock.setPaused(!playing, at: CACurrentMediaTime()) }
            .onScrollVisibilityChange { isVisible = $0 }
        }
    }

    private func frame(at elapsed: TimeInterval) -> CGImage? {
        let duration = AnimatedImageKeyframeSchedule.duration(for: image.frameDurations)
        if !isLooping, elapsed >= duration { return image.frames.last }
        var remaining = elapsed.truncatingRemainder(dividingBy: duration)
        for (index, duration) in image.frameDurations.enumerated() {
            if remaining < duration { return image.frames[index] }
            remaining -= duration
        }
        return image.frames.last
    }
}
