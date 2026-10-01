import AppKit
import CoreText
import SakuraCordModels

nonisolated func coreTextLine(_ value: Any) -> CTLine {
    let object = value as AnyObject
    precondition(CFGetTypeID(object) == CTLineGetTypeID())
    return unsafeDowncast(object, to: CTLine.self)
}

enum NativeTimelineSemanticColor {
    static func opacity(
        _ color: NSColor,
        _ multiplier: CGFloat
    ) -> NSColor {
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        return resolved.withAlphaComponent(
            resolved.alphaComponent * min(max(multiplier, 0), 1)
        )
    }
}

nonisolated enum TimelineInlineVideoPolicy {
    static func canvasOwnsLoadingSurface(
        mediaIsVideo: Bool,
        autoplaysInline: Bool
    ) -> Bool {
        !mediaIsVideo || !autoplaysInline
    }
}

enum NativeTimelineDateSeparatorMetrics {
    static let rowHeight: CGFloat = 37
    static let verticalPadding: CGFloat = 12
    static let lineSpacing: CGFloat = 10
    static let labelHeight: CGFloat = 13

    static var font: NSFont {
        .systemFont(ofSize: 10, weight: .semibold)
    }

    static func labelWidth(_ label: String) -> CGFloat {
        let attributed = NSAttributedString(
            string: label,
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        return ceil(
            CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        )
    }

    static func labelFrame(
        for label: String,
        in frame: CGRect
    ) -> CGRect {
        let width = labelWidth(label)
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.minY + verticalPadding,
            width: width,
            height: labelHeight
        )
    }
}

enum NativeTimelineUnreadSeparatorMetrics {
    static let rowHeight: CGFloat = 29
    static let capsuleHeight: CGFloat = 19
    static let verticalPadding: CGFloat = 5
}

/// Text rules for the timeline thread card, matching Discord's client.
nonisolated enum NativeTimelineThreadCard {
    static let height: CGFloat = 54
    /// Discord capped message counts at 50 for threads created before July 2022.
    private static let cappedCountCutoff = Date(timeIntervalSince1970: 1_656_712_657)

    static func countText(_ thread: MessageThreadSummary) -> String {
        let count = thread.messageCount
        guard count > 0 else { return "See Thread ›" }
        guard count > 1 else { return "1 Message ›" }
        let shown = if count >= 100_000 {
            "100k+"
        } else if count >= 50, thread.id.createdAt <= cappedCountCutoff {
            "50+"
        } else {
            "\(count)"
        }
        return "\(shown) Messages ›"
    }

    static func activityText(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let day: TimeInterval = 86_400
        return switch seconds {
        case ..<3_600: "\(max(1, Int(seconds / 60)))m ago"
        case ..<day: "\(Int(seconds / 3_600))h ago"
        case ..<(30 * day): "\(Int(seconds / day))d ago"
        case ..<(360 * day): ">30d ago"
        default: date.formatted(date: .long, time: .omitted)
        }
    }
}

enum NativeTimelineReplyMetrics {
    static let horizontalSpacing: CGFloat = 5

    static var authorFont: NSFont {
        .systemFont(
            ofSize: NSFont.preferredFont(
                forTextStyle: .caption2
            ).pointSize,
            weight: .semibold
        )
    }

    static var summaryFont: NSFont {
        .preferredFont(forTextStyle: .caption1)
    }

    static func textWidth(
        _ value: String,
        font: NSFont
    ) -> CGFloat {
        let attributed = NSAttributedString(
            string: value,
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        return ceil(
            CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        )
    }
}
