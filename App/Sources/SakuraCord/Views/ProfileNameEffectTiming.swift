import Foundation

enum ProfileNameEffectTiming {
    /// CSS keyframe easing applies independently to each interval.
    static func value(_ progress: Double, stops: [(Double, Double)], control: (first: (Double, Double), second: (Double, Double)) = ((0.44, 0.29), (0.48, 1))) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if progress <= first.0 { return first.1 }
        for index in 1 ..< stops.count where progress <= stops[index].0 {
            let previous = stops[index - 1]
            let next = stops[index]
            let fraction = (progress - previous.0) / (next.0 - previous.0)
            return previous.1 + (next.1 - previous.1) * bezier(fraction, control: control)
        }
        return last.1
    }

    private static func bezier(_ value: Double, control: (first: (Double, Double), second: (Double, Double))) -> Double {
        func coordinate(_ progress: Double, _ first: Double, _ second: Double) -> Double {
            3 * (1 - progress) * (1 - progress) * progress * first + 3 * (1 - progress) * progress * progress * second + progress * progress * progress
        }
        var lower = 0.0
        var upper = 1.0
        for _ in 0 ..< 18 {
            let middle = (lower + upper) / 2
            if coordinate(middle, control.first.0, control.second.0) < value { lower = middle } else { upper = middle }
        }
        return coordinate((lower + upper) / 2, control.first.1, control.second.1)
    }
}
