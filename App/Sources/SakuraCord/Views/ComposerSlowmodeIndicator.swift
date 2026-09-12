import SakuraCordModels
import SwiftUI

struct ComposerSlowmodeIndicator: View {
    let model: AppModel
    let channelID: ChannelID
    @State private var isHovering = false

    var body: some View {
        let configuration = model.slowmodeConfiguration(in: channelID)
        if configuration.interval > 0 {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = model.slowmodeRemaining(in: channelID, now: context.date)
                let title = remaining > 0
                    ? Self.countdown(remaining)
                    : (configuration.immune ? "Slowmode Immune" : "Slowmode is enabled")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "stopwatch.fill")
                    Text(title)
                }
                    .font(.caption)
                    .monospacedDigit()
                    .keyframeAnimator(
                        initialValue: 0.0,
                        trigger: model.composer.slowmode.rejectedAttempts[channelID, default: 0]
                    ) { content, flash in
                        content.foregroundStyle(Color.secondary.mix(with: .red, by: flash))
                    } keyframes: { _ in
                        LinearKeyframe(1, duration: 0.06)
                        LinearKeyframe(1, duration: 0.16)
                        LinearKeyframe(0, duration: 0.18)
                    }
                    .contentShape(Rectangle())
                    .onModalHover { isHovering = $0 }
                    .nativeHoverPopover(isPresented: $isHovering) {
                        Text("Slowmode is enabled. Members can send one message every \(Self.intervalDescription(configuration.interval)).")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .frame(width: 250)
                            .padding(12)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, ChatChromeMetrics.composerWindowInset)
            .padding(.trailing, trailingInset)
            .padding(.bottom, 5)
        }
    }

    private var trailingInset: CGFloat {
        let inputEdgeInset: CGFloat = switch model.appearanceSettings.composerBarAppearance {
        case .defaultStyle:
            ChatChromeMetrics.composerControlHeight
                + ChatChromeMetrics.composerSegmentSpacing
                + ChatChromeMetrics.composerCornerRadius / 2
        case .legacy:
            ChatChromeMetrics.composerMinimumCornerRadius / 2
        }
        return ChatChromeMetrics.composerWindowInset + inputEdgeInset
    }

    private static func countdown(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
        return String(format: "%d:%02d", minutes, remainder)
    }

    private static func intervalDescription(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(
            allowed: [.hours, .minutes, .seconds], width: .wide
        ))
    }
}
