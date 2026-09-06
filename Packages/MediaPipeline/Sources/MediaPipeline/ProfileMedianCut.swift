// Adapted from quantize.js, Copyright 2008 Nick Rabinowitz and
// Copyright 2014 Olivier Lesnicki, MIT license. See docs/THIRD_PARTY_NOTICES.md.

/// Modified median cut quantization. Queue insertion order is significant:
/// equal-population boxes must retain the ordering of the reference algorithm.
enum ProfileMedianCut {
    static func palette(pixels: [UInt32]) -> [UInt32] {
        guard !pixels.isEmpty else { return [0] }
        var histogram = [Int](repeating: 0, count: 32_768)
        var lower = [31, 31, 31]
        var upper = [0, 0, 0]
        for pixel in pixels {
            let channels = [Int(pixel >> 19 & 31), Int(pixel >> 11 & 31), Int(pixel >> 3 & 31)]
            histogram[index(channels[0], channels[1], channels[2])] += 1
            for axis in 0 ..< 3 {
                lower[axis] = min(lower[axis], channels[axis])
                upper[axis] = max(upper[axis], channels[axis])
            }
        }
        var population = [Box(lower: lower, upper: upper, histogram: histogram)]
        subdivide(&population, target: 3.75, histogram: histogram, byVolume: false)
        // The first queue is drained from highest to lowest population before
        // the second queue begins ordering by population times colour volume.
        population = ordered(population, byVolume: false)
        var volume = Array(population.reversed())
        subdivide(&volume, target: Double(5 - volume.count), histogram: histogram, byVolume: true)
        return ordered(volume, byVolume: true).reversed().map(\.average)
    }

    private static func index(_ red: Int, _ green: Int, _ blue: Int) -> Int {
        red << 10 | green << 5 | blue
    }

    private static func ordered(_ boxes: [Box], byVolume: Bool) -> [Box] {
        boxes.enumerated().sorted { lhs, rhs in
            let left = lhs.element.count * (byVolume ? lhs.element.volume : 1)
            let right = rhs.element.count * (byVolume ? rhs.element.volume : 1)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private static func subdivide(_ boxes: inout [Box], target: Double, histogram: [Int], byVolume: Bool) {
        var colors = 1
        for _ in 0 ..< 1_000 {
            boxes = ordered(boxes, byVolume: byVolume)
            guard let box = boxes.popLast() else { return }
            guard box.count > 0 else {
                boxes.append(box)
                continue
            }
            let split = cut(box, histogram: histogram)
            boxes.append(contentsOf: split)
            if split.count == 2 { colors += 1 }
            if Double(colors) >= target { return }
        }
    }

    private static func cut(_ box: Box, histogram: [Int]) -> [Box] {
        guard box.count > 1 else { return [box] }
        let widths = (0 ..< 3).map { box.upper[$0] - box.lower[$0] + 1 }
        let axis = widths[0] >= max(widths[1], widths[2]) ? 0 : (widths[1] >= widths[2] ? 1 : 2)
        let start = box.lower[axis]
        let end = box.upper[axis]
        var cumulative = [Int](repeating: 0, count: 32)
        box.forEachBin { red, green, blue in
            cumulative[[red, green, blue][axis]] += histogram[index(red, green, blue)]
        }
        var total = 0
        for value in start ... end {
            total += cumulative[value]
            cumulative[value] = total
        }
        guard let median = (start ... end).first(where: { cumulative[$0] > total / 2 }) else { return [box] }
        let left = median - start
        let right = end - median
        var boundary = left <= right ? min(end - 1, median + right / 2) : max(start, Int(Double(median - 1) - Double(left) / 2))
        while boundary < end, boundary < start || cumulative[boundary] == 0 { boundary += 1 }
        while boundary > start, total - cumulative[boundary] == 0, cumulative[boundary - 1] > 0 { boundary -= 1 }
        var firstUpper = box.upper
        firstUpper[axis] = boundary
        var secondLower = box.lower
        secondLower[axis] = boundary + 1
        return [Box(lower: box.lower, upper: firstUpper, histogram: histogram),
                Box(lower: secondLower, upper: box.upper, histogram: histogram)]
    }

    private struct Box {
        let lower: [Int]
        let upper: [Int]
        let count: Int
        let volume: Int
        let average: UInt32

        init(lower: [Int], upper: [Int], histogram: [Int]) {
            self.lower = lower
            self.upper = upper
            volume = (0 ..< 3).reduce(1) { $0 * max(0, upper[$1] - lower[$1] + 1) }
            var count = 0
            var sums = [0, 0, 0]
            if volume > 0 {
                for red in lower[0] ... upper[0] {
                    for green in lower[1] ... upper[1] {
                        for blue in lower[2] ... upper[2] {
                            let population = histogram[index(red, green, blue)]
                            count += population
                            sums[0] += population * (red * 8 + 4)
                            sums[1] += population * (green * 8 + 4)
                            sums[2] += population * (blue * 8 + 4)
                        }
                    }
                }
            }
            self.count = count
            let channels = (0 ..< 3).map { axis in
                min(255, count > 0 ? sums[axis] / count : 4 * (lower[axis] + upper[axis] + 1))
            }
            average = UInt32(channels[0] << 16 | channels[1] << 8 | channels[2])
        }

        func forEachBin(_ action: (Int, Int, Int) -> Void) {
            guard volume > 0 else { return }
            for red in lower[0] ... upper[0] {
                for green in lower[1] ... upper[1] {
                    for blue in lower[2] ... upper[2] { action(red, green, blue) }
                }
            }
        }
    }
}
