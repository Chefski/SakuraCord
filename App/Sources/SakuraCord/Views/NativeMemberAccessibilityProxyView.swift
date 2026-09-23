import AppKit
import CoreText
import OSLog
import SakuraCordModels
import SwiftUI

@MainActor
final class NativeMemberAccessibilityProxyView: NSButton {
    var member: Member? {
        didSet {
            guard let member else { return }
            setAccessibilityLabel(member.user.displayName)
            setAccessibilityHelp(member.user.username)
            let activity = member.memberListActivityText.flatMap {
                $0.isEmpty ? nil : NativeMemberActivityPresentation.accessibilityText($0)
            }
            setAccessibilityValue(activity.map {
                member.isListeningToMusic ? "Listening to music, \($0)" : $0
            })
            toolTip = member.user.username
        }
    }
    var activation: ((Member) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        imagePosition = .noImage
        wantsLayer = true
        layer?.backgroundColor = .clear
        setAccessibilityRole(.button)
        target = self
        action = #selector(activateMember)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func activateMember() {
        guard let member else { return }
        activation?(member)
    }
}
