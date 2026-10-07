import AppKit
import CoreText
import SakuraCordModels

struct NativeServerCardContent {
    let guildID: GuildID
    let name: String
    let iconURL: URL?
    let inviter: User?
    let brandColor: UInt32?
    let description: String?
    let traits: [ServerInvite.Trait]
    let memberCount: Int?
    let onlineCount: Int?

    init(invite: ServerInvite) {
        guildID = invite.guildID
        name = invite.name
        iconURL = invite.iconURL
        inviter = invite.inviter
        brandColor = invite.brandColor
        description = invite.description
        traits = invite.traits
        memberCount = invite.memberCount
        onlineCount = invite.onlineCount
    }

    init(profile: GuildProfile, iconURL: URL?, adaptiveColor: UInt32? = nil) {
        guildID = profile.id
        name = profile.name
        self.iconURL = iconURL
        inviter = nil
        brandColor = profile.brandColor ?? adaptiveColor
        description = profile.description
        traits = profile.traits.map { .init(label: $0.label, emoji: $0.emojiName, emojiURL: $0.emojiURL) }
        memberCount = profile.memberCount
        onlineCount = profile.onlineCount
    }
}

struct NativeTimelineInviteLayout {
    static var cornerRadius: CGFloat { InterfaceScale.metric(28) }

    struct Label {
        var text: String
        var frame: CGRect
        var size: CGFloat = 14
        var bold = false
        var secondary = false
        var lineHeight: CGFloat = 20

        func attributedText(color: NSColor) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = InterfaceScale.metric(lineHeight)
            paragraph.maximumLineHeight = InterfaceScale.metric(lineHeight)
            paragraph.lineBreakMode = .byWordWrapping
            return NSAttributedString(string: text, attributes: [
                .font: NSFont.interfaceSystemFont(ofSize: size, weight: bold ? .semibold : .regular),
                .foregroundColor: color, .paragraphStyle: paragraph
            ])
        }
    }
    struct Trait {
        var value: ServerInvite.Trait
        var frame: CGRect
    }
    private struct TraitArrangement {
        var regions: [Trait]
        var height: CGFloat
        var overflow: Bool
    }
    let reference: ServerInviteReference?
    let componentID: String
    let frame: CGRect
    let bannerFrame: CGRect
    let iconFrame: CGRect
    let inviterAvatarFrame: CGRect?
    let gradientColor: UInt32?
    let countDots: [CGRect]
    let labels: [Label]
    let traits: [Trait]
    let buttonFrame: CGRect
    let detailsFrame: CGRect?
    let isExpanded: Bool
    let hasCollapsedContent: Bool
    let contentBottom: CGFloat
    let invite: ServerInvite?
    let content: NativeServerCardContent?
    let buttonTitle: String
    let isDisabled: Bool
    let isUnavailable: Bool
    let error: String?

    var accessibilityLabel: String {
        (labels.map(\.text) + (content?.traits.map(\.label) ?? [])).joined(separator: ". ")
    }

    init(reference: ServerInviteReference? = nil, index: Int, origin: CGPoint, maximumWidth: CGFloat,
         model: AppModel?, isOwnMessage: Bool, fillsWidth: Bool = false, preview: NativeServerCardContent? = nil) {
        self.reference = reference
        componentID = "server-invite:\(index):\(reference?.code ?? preview?.guildID.description ?? "")"
        let entry = reference.flatMap { model?.serverInvites.entries[$0] }
        invite = entry?.isUnavailable == true ? nil : entry?.invite
        content = preview ?? invite.map(NativeServerCardContent.init)
        gradientColor = content?.brandColor ?? entry?.adaptiveColor
        isUnavailable = entry?.isUnavailable == true
        error = entry?.error ?? invite.flatMap {
            model?.serverRailGuildsByID[$0.guildID] == nil ? $0.unsupportedJoinReason : nil
        }
        isExpanded = preview != nil || reference.map { model?.serverInvites.expanded.contains($0) == true } == true
        let width = fillsWidth ? maximumWidth : min(isUnavailable ? InterfaceScale.metric(432) : InterfaceScale.metric(302), maximumWidth)
        let originX = origin.x, originY = origin.y, inner = max(1, width - InterfaceScale.metric(32))
        bannerFrame = CGRect(x: originX, y: originY, width: width, height: content == nil ? 0 : InterfaceScale.metric(72))
        iconFrame = isUnavailable ? CGRect(x: originX + InterfaceScale.metric(16), y: originY + InterfaceScale.metric(46), width: InterfaceScale.metric(48), height: InterfaceScale.metric(48))
            : CGRect(x: originX + InterfaceScale.metric(19), y: originY + InterfaceScale.metric(41), width: InterfaceScale.metric(64), height: InterfaceScale.metric(64))
        var labels: [Label] = []
        var traits: [Trait] = []
        var hiddenTraits = false
        var inviterAvatar: CGRect?
        var countDots: [CGRect] = []
        var cursor = originY + InterfaceScale.metric(16)
        if let invite = content {
            cursor = originY + InterfaceScale.metric(116)
            inviterAvatar = Self.appendIdentity(invite, currentUserID: model?.currentUser?.id,
                                                originX: originX + InterfaceScale.metric(16), width: inner, cursor: &cursor, labels: &labels)
            Self.appendCounts(invite, originX: originX + InterfaceScale.metric(16), width: inner, cursor: &cursor, labels: &labels, dots: &countDots)
            if let description = invite.description, !description.isEmpty {
                cursor += InterfaceScale.metric(12)
                let height = Self.height(description, width: inner, size: 14)
                labels.append(.init(text: description, frame: CGRect(x: originX + InterfaceScale.metric(16), y: cursor, width: inner, height: height), secondary: true))
                cursor += height
            }
            if !invite.traits.isEmpty {
                cursor += InterfaceScale.metric(8)
                let arranged = Self.arrangeTraits(invite.traits, origin: CGPoint(x: originX + InterfaceScale.metric(16), y: cursor), width: inner, expanded: isExpanded)
                traits = arranged.regions
                hiddenTraits = arranged.overflow
                cursor += arranged.height
            }
        } else {
            labels.append(.init(text: isOwnMessage ? "You sent an invite, but" : "You've been invited, but",
                                frame: CGRect(x: originX + InterfaceScale.metric(16), y: cursor, width: inner, height: InterfaceScale.metric(20)), secondary: true))
            cursor += InterfaceScale.metric(28)
            let detailX = originX + (isUnavailable ? InterfaceScale.metric(80) : InterfaceScale.metric(16))
            let detailWidth = max(1, inner - (isUnavailable ? InterfaceScale.metric(64) : 0))
            labels.append(.init(text: isUnavailable ? "Invalid Invite" : entry?.error == nil ? "Loading invite…" : "Invite unavailable",
                                frame: CGRect(x: detailX, y: cursor + (isUnavailable ? InterfaceScale.metric(6) : 0), width: detailWidth, height: InterfaceScale.metric(22)), size: 16, bold: true))
            cursor += InterfaceScale.metric(26)
            let detail = isUnavailable ? (isOwnMessage ? "Try sending a new invite" : "Ask for a new invite") : entry?.error
            if let detail {
                let height = Self.height(detail, width: detailWidth, size: 14)
                labels.append(.init(text: detail, frame: CGRect(x: detailX, y: cursor + (isUnavailable ? InterfaceScale.metric(4) : 0), width: detailWidth, height: height), secondary: true))
                cursor += height + (isUnavailable ? InterfaceScale.metric(8) : 0)
            }
        }
        if invite != nil, let error {
            cursor += InterfaceScale.metric(12)
            let height = Self.height(error, width: inner, size: 13)
            labels.append(.init(text: error, frame: CGRect(x: originX + InterfaceScale.metric(16), y: cursor, width: inner, height: height), size: 13))
            cursor += height
        }
        let canCollapse = preview == nil && invite != nil && cursor - originY > InterfaceScale.metric(292) && error == nil
        let collapsed = canCollapse && !isExpanded
        hasCollapsedContent = collapsed
        if collapsed { cursor = originY + InterfaceScale.metric(230) }
        contentBottom = cursor
        if canCollapse || hiddenTraits, isExpanded {
            detailsFrame = CGRect(x: originX + InterfaceScale.metric(16), y: cursor + InterfaceScale.metric(8), width: inner, height: InterfaceScale.metric(24))
            cursor += InterfaceScale.metric(32)
        } else {
            detailsFrame = collapsed ? CGRect(x: originX, y: originY, width: width, height: cursor - originY + InterfaceScale.metric(8))
                : hiddenTraits ? traits.last?.frame : nil
        }
        let showsButton = preview == nil && !isUnavailable
        buttonFrame = CGRect(x: originX + InterfaceScale.metric(16), y: cursor + InterfaceScale.metric(16), width: inner, height: showsButton ? InterfaceScale.metric(32) : 0)
        frame = CGRect(x: originX, y: originY, width: width, height: cursor + (showsButton ? InterfaceScale.metric(64) : InterfaceScale.metric(16)) - originY)
        inviterAvatarFrame = inviterAvatar
        self.countDots = countDots
        self.labels = labels
        self.traits = traits
        (buttonTitle, isDisabled) = Self.action(for: invite, entry: entry, model: model)
    }

    private static func appendIdentity(_ invite: NativeServerCardContent, currentUserID: UserID?, originX: CGFloat, width: CGFloat,
                                       cursor: inout CGFloat, labels: inout [Label]) -> CGRect? {
        let nameHeight = height(invite.name, width: width, size: 16, bold: true)
        labels.append(.init(text: invite.name, frame: CGRect(x: originX, y: cursor, width: width, height: nameHeight), size: 16, bold: true))
        cursor += nameHeight
        guard let inviter = invite.inviter else { return nil }
        let text = inviter.id == currentUserID ? "You sent an invite to join \(invite.name)"
            : "\(inviter.displayName) invited you to \(invite.name)"
        let textHeight = height(text, width: width - InterfaceScale.metric(20), size: 14, lineHeight: 18)
        labels.append(.init(
            text: text,
            frame: CGRect(x: originX + InterfaceScale.metric(20), y: cursor, width: width - InterfaceScale.metric(20), height: textHeight),
            secondary: true,
            lineHeight: 18
        ))
        let avatar = CGRect(x: originX, y: cursor + (textHeight - InterfaceScale.metric(16)) / 2, width: InterfaceScale.metric(16), height: InterfaceScale.metric(16))
        cursor += textHeight
        return avatar
    }

    private static func appendCounts(_ invite: NativeServerCardContent, originX: CGFloat, width: CGFloat, cursor: inout CGFloat,
                                     labels: inout [Label], dots: inout [CGRect]) {
        var countX = originX
        for count in [invite.onlineCount.map { "\($0.formatted()) Online" },
                      invite.memberCount.map { "\($0.formatted()) \($0 == 1 ? "Member" : "Members")" }].compactMap({ $0 }) {
            dots.append(CGRect(x: countX, y: cursor + InterfaceScale.metric(6), width: InterfaceScale.metric(8), height: InterfaceScale.metric(8)))
            let textWidth = ceil((count as NSString).size(withAttributes: [.font: NSFont.interfaceSystemFont(ofSize: 14)]).width)
            labels.append(.init(
                text: count,
                frame: CGRect(x: countX + InterfaceScale.metric(12), y: cursor, width: min(textWidth + 1, originX + width - countX - InterfaceScale.metric(12)), height: InterfaceScale.metric(20)),
                secondary: true
            ))
            countX += textWidth + InterfaceScale.metric(20)
        }
        if countX > originX { cursor += InterfaceScale.metric(20) }
        let created = Date(timeIntervalSince1970: Double((invite.guildID.rawValue >> 22) + 1_420_070_400_000) / 1_000)
        labels.append(.init(text: "Est. \(created.formatted(.dateTime.month(.abbreviated).year()))",
                            frame: CGRect(x: originX, y: cursor, width: width, height: InterfaceScale.metric(20)), secondary: true))
        cursor += InterfaceScale.metric(20)
    }

    private static func action(for invite: ServerInvite?, entry: ServerInvitePresentationStore.Entry?, model: AppModel?)
        -> (String, Bool) {
        if let invite, model?.serverInvites.leaving.contains(invite.guildID) == true { return ("Leaving…", true) }
        if let invite, model?.serverInvites.joining.contains(invite.guildID) == true { return ("Joining…", true) }
        if let member = invite.flatMap({ model?.serverRailGuildsByID[$0.guildID] }) {
            return (member.isUnavailable ? "Server unavailable" : "Go to Server", member.isUnavailable)
        }
        if invite?.unsupportedJoinReason != nil { return ("Open in Discord", false) }
        return (invite != nil ? "Join Server" : entry?.error != nil ? "Try Again" : "Loading…",
                entry?.isLoading != false && invite == nil)
    }

    private static func arrangeTraits(_ values: [ServerInvite.Trait], origin: CGPoint, width: CGFloat, expanded: Bool)
        -> TraitArrangement {
        var regions: [Trait] = []
        var cursorX = origin.x
        var cursorY = origin.y
        let rowStep = InterfaceScale.metric(32)
        let traitHeight = InterfaceScale.metric(28)
        let gap = InterfaceScale.metric(4)
        for trait in values.prefix(5) {
            let labelWidth = (trait.label as NSString).size(withAttributes: [.font: NSFont.interfaceSystemFont(ofSize: 14)]).width
            let traitWidth = min(width, ceil(labelWidth) + InterfaceScale.metric(16) + (trait.emoji != nil || trait.emojiURL != nil ? InterfaceScale.metric(20) : 0))
            if cursorX + traitWidth > origin.x + width, cursorX > origin.x { cursorX = origin.x; cursorY += rowStep }
            regions.append(.init(value: trait, frame: CGRect(x: cursorX, y: cursorY, width: traitWidth, height: traitHeight)))
            cursorX += traitWidth + gap
        }
        let overflow = cursorY > origin.y + rowStep
        if overflow, !expanded {
            regions.removeAll { $0.frame.minY > origin.y + rowStep }
            let moreWidth: CGFloat = InterfaceScale.metric(76)
            while let last = regions.last, last.frame.minY == origin.y + rowStep,
                  last.frame.maxX + gap + moreWidth > origin.x + width { regions.removeLast() }
            let moreX = regions.last.flatMap { $0.frame.minY == origin.y + rowStep ? $0.frame.maxX + gap : nil } ?? origin.x
            regions.append(.init(value: .init(label: "+\(values.count - regions.count) more"),
                                frame: CGRect(x: moreX, y: origin.y + rowStep, width: moreWidth, height: traitHeight)))
            cursorY = origin.y + rowStep
        }
        return TraitArrangement(regions: regions, height: cursorY + traitHeight - origin.y, overflow: overflow)
    }

    private static func height(_ text: String, width: CGFloat, size: CGFloat, bold: Bool = false, lineHeight: CGFloat = 20) -> CGFloat {
        let value = Label(text: text, frame: .zero, size: size, bold: bold, lineHeight: lineHeight).attributedText(color: .labelColor)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(value), CFRange(), nil,
                                                                  CGSize(width: width, height: .greatestFiniteMagnitude), nil).height
        let line = InterfaceScale.metric(lineHeight)
        return max(line, ceil(measured / line) * line)
    }
}
