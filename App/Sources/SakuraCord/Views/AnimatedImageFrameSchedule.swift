import Foundation

/// The same source-frame and effect-layer timing used by compositor animations,
/// expressed as a frame index for animations whose raster set exceeds the budget.
nonisolated enum AnimatedImageFrameSchedule {
    static func frameIndex(
        elapsed: TimeInterval,
        durations: [TimeInterval],
        playCount: Int?,
        isLooping: Bool,
        activeDuration: TimeInterval?,
        loopDelay: TimeInterval
    ) -> Int? {
        guard !durations.isEmpty, elapsed >= 0 else { return nil }
        let sourceDuration = AnimatedImageKeyframeSchedule.duration(for: durations)
        let position: TimeInterval
        if let activeDuration {
            let sourceLimit = playCount.flatMap { $0 > 0 ? sourceDuration * Double($0) : nil }
            if isLooping, loopDelay <= 0 {
                if let sourceLimit, elapsed >= sourceLimit { return durations.count - 1 }
                position = elapsed.truncatingRemainder(dividingBy: sourceDuration)
            } else {
                let active = activeDuration > 0 ? activeDuration : sourceDuration
                let cyclePosition = isLooping
                    ? elapsed.truncatingRemainder(dividingBy: active + max(0, loopDelay))
                    : elapsed
                guard cyclePosition < active else { return nil }
                if let sourceLimit, cyclePosition >= sourceLimit { return durations.count - 1 }
                position = cyclePosition.truncatingRemainder(dividingBy: sourceDuration)
            }
        } else {
            // Ordinary one-shot canvases return to their model-layer poster
            // when the existing remove-on-completion animation ends.
            if !isLooping, elapsed >= sourceDuration { return 0 }
            position = elapsed.truncatingRemainder(dividingBy: sourceDuration)
        }
        var end: TimeInterval = 0
        for (index, duration) in durations.enumerated() {
            end += duration
            if position < end { return index }
        }
        return durations.count - 1
    }
}
