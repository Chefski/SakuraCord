import AppKit
import CoreText
import SakuraCordModels

struct NativeTimelinePollLayout {
    struct Answer {
        let id: Int
        let frame: CGRect
        let textFrame: CGRect
        let emojiFrame: CGRect?
    }
    let frame: CGRect
    let questionFrame: CGRect
    let instructionFrame: CGRect
    let answers: [Answer]
    let votesFrame: CGRect
    let expiryFrame: CGRect
    let revealFrame: CGRect
    let submitFrame: CGRect

    init(poll: MessagePoll, x originX: CGFloat, y originY: CGFloat, width availableWidth: CGFloat) {
        let width = min(456, availableWidth)
        let inner = max(1, width - 32)
        var cursor = originY + 16
        let questionHeight = Self.height(poll.question, width: inner, font: .systemFont(ofSize: 15, weight: .semibold))
        questionFrame = CGRect(x: originX + 16, y: cursor, width: inner, height: questionHeight)
        cursor += questionHeight + 5
        instructionFrame = CGRect(x: originX + 16, y: cursor, width: inner, height: poll.isClosed() ? 0 : 17)
        cursor += poll.isClosed() ? 7 : 29
        answers = poll.answers.map { answer in
            let emojiWidth: CGFloat = answer.emoji == nil ? 0 : 30
            let reserved: CGFloat = poll.selectedAnswerIDs.contains(answer.id) ? 142 : 110
            let textWidth = max(1, inner - reserved - emojiWidth)
            let height = max(50, Self.height(answer.text, width: textWidth, font: .systemFont(ofSize: 13)) + 24)
            let rect = CGRect(x: originX + 16, y: cursor, width: inner, height: height)
            defer { cursor += height + 8 }
            return Answer(id: answer.id, frame: rect,
                          textFrame: CGRect(x: rect.minX + 12 + emojiWidth, y: rect.minY + 12, width: textWidth, height: height - 24),
                          emojiFrame: answer.emoji == nil ? nil : CGRect(x: rect.minX + 12, y: rect.midY - 11, width: 22, height: 22))
        }
        cursor += 4
        let stacksFooter = inner < 384 && !poll.isClosed()
        votesFrame = CGRect(x: originX + 16, y: cursor, width: min(80, inner), height: NativeTimelineComponentButtonMetrics.height)
        expiryFrame = CGRect(x: originX + 104, y: cursor,
                             width: max(0, inner - (stacksFooter || poll.isClosed() ? 88 : 294)), height: NativeTimelineComponentButtonMetrics.height)
        if stacksFooter { cursor += 38 }
        let submitWidth = min(94, inner * 0.45)
        submitFrame = CGRect(x: originX + width - 16 - submitWidth, y: cursor, width: submitWidth, height: NativeTimelineComponentButtonMetrics.height)
        let revealWidth = min(120, max(0, inner - submitWidth - 6))
        revealFrame = CGRect(x: submitFrame.minX - 6 - revealWidth, y: cursor, width: revealWidth, height: NativeTimelineComponentButtonMetrics.height)
        frame = CGRect(x: originX, y: originY, width: width, height: cursor + 44 - originY)
    }

    static func resultButtonFrame(in frame: CGRect) -> CGRect {
        let height = NativeTimelineComponentButtonMetrics.height
        return CGRect(x: frame.maxX - 100, y: frame.midY - height / 2, width: 86, height: height)
    }

    private static func height(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let value = NSAttributedString(string: text, attributes: [.font: font])
        let setter = CTFramesetterCreateWithAttributedString(value)
        return ceil(CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                     CGSize(width: width, height: .greatestFiniteMagnitude), nil).height)
    }
}

struct NativeTimelinePollPresentation {
    static let voteAnimationDuration: TimeInterval = 0.48
    var selected: Set<Int> = []
    var revealsResults = false
    var isSubmitting = false
    var hoveredControl: NativeTimelinePollTarget.Control?
    var pressedControl: NativeTimelinePollTarget.Control?
    var fractions: [Int: CGFloat] = [:]

    func showsResults(for poll: MessagePoll) -> Bool {
        revealsResults || poll.isClosed() || !poll.selectedAnswerIDs.isEmpty
    }
}

struct NativeTimelinePollTarget: Equatable {
    enum Control: Equatable { case answer(Int), votes, reveal, submit, original }
    let messageID: MessageID
    let control: Control
}

extension NativeTimelineRowPainter {
    static func pollSurface(in frame: CGRect) {
        let radius = ChatChromeMetrics.composerCornerRadius
        NativeTimelineSemanticColor.opacity(.controlBackgroundColor, 0.45).setFill()
        NSBezierPath(concentricRoundedRect: frame, cornerRadius: radius).fill()
        NativeTimelineSemanticColor.opacity(.labelColor, 0.10).setStroke()
        let border = NSBezierPath(concentricRoundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius - 0.5)
        border.lineWidth = 1
        border.stroke()
    }

    static func pollButton(_ title: String, in frame: CGRect, control: NativeTimelinePollTarget.Control,
                           state: NativeTimelinePollPresentation, isEnabled: Bool = true, isProminent: Bool = false) {
        sakuraCordButton(title: title, frame: frame, isHovered: isEnabled && state.hoveredControl == control,
                        pressProgress: state.pressedControl == control ? 1 : 0,
                        colors: [isProminent ? .sakuraCordAccentColor : .controlColor],
                        foreground: isProminent ? .white : .labelColor, isEnabled: isEnabled)
    }

    static func drawPoll(_ input: NativeTimelineMessageDrawInput) {
        guard let poll = input.row.message.poll, let layout = input.layout.pollLayout else { return }
        let state = input.pollPresentation
        pollSurface(in: layout.frame)
        text(poll.question, in: layout.questionFrame, font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor, lineBreakMode: .byWordWrapping)
        text(poll.isClosed() ? "" : poll.allowsMultipleAnswers ? "Select one or more answers" : "Select one answer",
             in: layout.instructionFrame, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        for region in layout.answers {
            guard let answer = poll.answers.first(where: { $0.id == region.id }) else { continue }
            drawPollAnswer(answer, region: region, poll: poll, state: state)
        }
        drawPollFooter(poll, layout: layout, state: state, isConfirmed: input.row.message.outboxState == .confirmed)
    }

    private static func drawPollAnswer(_ answer: PollAnswer, region: NativeTimelinePollLayout.Answer,
                                       poll: MessagePoll, state: NativeTimelinePollPresentation) {
        let results = state.showsResults(for: poll)
        let selected = results ? poll.selectedAnswerIDs.contains(answer.id) : state.selected.contains(answer.id)
        let highestCount = poll.results?.answerCounts.map(\.count).max() ?? 0
        let winner = poll.isClosed() && highestCount > 0 && poll.count(for: answer.id) == highestCount
        let hovered = state.hoveredControl == .answer(answer.id)
        let accent = NSColor.sakuraCordAccentColor
        let path = NSBezierPath(concentricRoundedRect: region.frame, cornerRadius: ChatChromeMetrics.composerCornerRadius - 4)
        NSColor.labelColor.withAlphaComponent(hovered ? 0.08 : 0.045).setFill()
        path.fill()
        if results {
            let fraction = state.fractions[answer.id] ?? (poll.totalVotes > 0 ? CGFloat(poll.count(for: answer.id)) / CGFloat(poll.totalVotes) : 0)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            ((selected || winner) ? accent.withAlphaComponent(0.25) : NSColor.labelColor.withAlphaComponent(0.12)).setFill()
            CGRect(x: region.frame.minX, y: region.frame.minY, width: region.frame.width * min(1, max(0, fraction)), height: region.frame.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        if selected || winner || (!results && hovered) {
            ((selected || winner) ? accent : NSColor.labelColor.withAlphaComponent(0.24)).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        drawPollEmoji(answer.emoji, frame: region.emojiFrame)
        text(answer.text, in: region.textFrame, font: .systemFont(ofSize: 13, weight: .medium),
             color: .labelColor, lineBreakMode: .byWordWrapping)
        if results {
            drawPollAnswerResult(answer, region: region, poll: poll, selected: selected)
        } else {
            let box = CGRect(x: region.frame.maxX - 32, y: region.frame.midY - 10, width: 20, height: 20)
            let radius: CGFloat = poll.allowsMultipleAnswers ? 5 : 10
            let indicator = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
            (selected ? accent : NSColor.secondaryLabelColor).setStroke()
            indicator.lineWidth = 1.5
            indicator.stroke()
            if selected {
                accent.setFill()
                if poll.allowsMultipleAnswers {
                    indicator.fill()
                    text("✓", in: box, font: .systemFont(ofSize: 14, weight: .semibold), color: .white, alignment: .center)
                } else {
                    NSBezierPath(ovalIn: box.insetBy(dx: 4, dy: 4)).fill()
                }
            }
        }
    }

    private static func drawPollEmoji(_ emoji: EmojiReference?, frame: CGRect?) {
        guard let emoji, let frame else { return }
        if let url = emoji.imageURL(size: 64), let image = mediaImage(for: .media(url, maximumPixelDimension: 64)) {
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else if emoji.id == nil {
            text(emoji.name, in: frame, font: .systemFont(ofSize: 20), color: .labelColor, lineBreakMode: .byClipping)
        }
    }

    private static func drawPollAnswerResult(_ answer: PollAnswer, region: NativeTimelinePollLayout.Answer,
                                             poll: MessagePoll, selected: Bool) {
        let trailing: CGFloat = selected ? 40 : 12
        let percentageFrame = CGRect(x: region.frame.maxX - trailing - 40, y: region.frame.midY - 10, width: 40, height: 20)
        let count = poll.count(for: answer.id)
        let percentage = poll.totalVotes > 0 ? Int((Double(count) / Double(poll.totalVotes) * 100).rounded()) : 0
        text(poll.results == nil ? "—" : "\(percentage)%", in: percentageFrame,
             font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor, alignment: .right)
        let countFrame = CGRect(x: percentageFrame.minX - 50, y: region.frame.midY - 10, width: 46, height: 20)
        text(poll.results == nil ? "—" : "\(count) \(count == 1 ? "vote" : "votes")", in: countFrame,
             font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor, alignment: .right)
        if selected {
            let box = CGRect(x: region.frame.maxX - 32, y: region.frame.midY - 10, width: 20, height: 20)
            NSColor.sakuraCordAccentColor.setFill()
            NSBezierPath(ovalIn: box).fill()
            text("✓", in: box, font: .systemFont(ofSize: 14, weight: .semibold), color: .white, alignment: .center)
        }
    }

    private static func drawPollFooter(_ poll: MessagePoll, layout: NativeTimelinePollLayout,
                                       state: NativeTimelinePollPresentation, isConfirmed: Bool) {
        let results = state.showsResults(for: poll)
        pollButton(poll.results == nil ? "— votes" : "\(poll.totalVotes) \(poll.totalVotes == 1 ? "vote" : "votes")",
                   in: layout.votesFrame, control: .votes, state: state)
        let remaining = max(0, Int((poll.expiry?.timeIntervalSinceNow ?? 0) / 60))
        let time = poll.isClosed() ? "Final results" : remaining >= 1440 ? "\(remaining / 1440)d left" : remaining >= 60 ? "\(remaining / 60)h left" : "\(max(1, remaining))m left"
        text(time, in: layout.expiryFrame, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        guard !poll.isClosed(), isConfirmed else { return }
        if poll.selectedAnswerIDs.isEmpty {
            pollButton(results ? "Back to vote" : "Show results", in: layout.revealFrame, control: .reveal, state: state)
        }
        if !results || !poll.selectedAnswerIDs.isEmpty {
            let removing = !poll.selectedAnswerIDs.isEmpty
            let enabled = !state.isSubmitting && (removing || !state.selected.isEmpty)
            pollButton(state.isSubmitting ? "…" : removing ? "Remove Vote" : "Vote",
                       in: layout.submitFrame, control: .submit, state: state, isEnabled: enabled, isProminent: !removing)
        }
    }
}
