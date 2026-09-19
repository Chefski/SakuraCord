import AppKit
import SakuraCordModels

extension NativeTimelineRowPainter {
    static func drawPollResult(_ input: NativeTimelineMessageDrawInput) {
        guard let result = input.row.message.pollResultSummary, let frame = input.layout.pollResultFrame else { return }
        pollSurface(in: frame)
        let label = result.winner ?? (result.totalVotes == 0 ? "There was no winner" : "The results were tied")
        text(label, in: CGRect(x: frame.minX + 14, y: frame.minY + 12, width: frame.width - 125, height: 22),
             font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let percentage = result.totalVotes > 0 ? Int((Double(result.winnerVotes) / Double(result.totalVotes) * 100).rounded()) : 0
        let detail = result.winner != nil ? "Winning answer · \(percentage)%" : result.totalVotes > 0 ? "\(percentage)%" : ""
        text(detail, in: CGRect(x: frame.minX + 14, y: frame.minY + 36, width: frame.width - 125, height: 16),
             font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let button = NativeTimelinePollLayout.resultButtonFrame(in: frame)
        pollButton("View Poll", in: button, control: .original, state: input.pollPresentation)
    }
}
