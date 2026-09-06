import MessageRendering
import SakuraCordModels
import SwiftUI

struct ProfileGameAnnouncementCard: View {
    let message: ProfileGameAnnouncement
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let poll = message.poll {
                Text(poll.question).font(.headline).lineLimit(3)
                ForEach(poll.answers.prefix(3)) { answer in
                    Text(answer.text).font(.callout).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 6))
                }
                if poll.answers.count > 3 { Text("\(poll.answers.count - 3) more options").font(.caption).foregroundStyle(.secondary) }
            } else {
                if let source = message.embedSource {
                    if let url = source.url { Link(url.absoluteString, destination: url).font(.caption).lineLimit(1) }
                    if let author = source.author {
                        HStack(spacing: 6) {
                            if let icon = author.proxyIconURL ?? author.iconURL {
                                ProfileWidgetImageView(url: icon).frame(width: 20, height: 20).clipShape(.circle)
                            }
                            Text(author.name).font(.caption.weight(.semibold)).lineLimit(1)
                        }
                    }
                }
                if let url = imageURL {
                    ProfileWidgetImageView(url: url, contentMode: .fill).frame(height: 160).clipped()
                }
                if let title = message.title { Text(DiscordMarkdown.attributed(title)).font(.headline).lineLimit(3) }
                if !message.body.isEmpty { Text(DiscordMarkdown.attributed(message.body)).font(.callout).lineLimit(5) }
            }
            HStack(spacing: 5) {
                if let source = message.embedSource {
                    if let icon = source.footer?.proxyIconURL ?? source.footer?.iconURL {
                        ProfileWidgetImageView(url: icon).frame(width: 16, height: 16)
                    }
                    if let name = source.footer?.text ?? source.provider?.name { Text("\(name) ·").lineLimit(1) }
                }
                Text(message.timestamp.formatted(date: .abbreviated, time: .omitted))
                Spacer(minLength: 0)
                if message.reactionCount > 0, message.poll == nil { Label(message.reactionCount.formatted(), systemImage: "face.smiling") }
            }.font(.caption).foregroundStyle(.secondary)
            if let expiry = message.poll?.expiry {
                Text(expiry > .now ? "Poll ends \(expiry.formatted(date: .abbreviated, time: .shortened))" : "Poll ended")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 280, alignment: .leading).padding(16)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 12))
    }

    private var imageURL: URL? {
        guard let media = message.media, let url = media.proxyURL ?? media.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let ratio = media.width.flatMap { width in media.height.flatMap { $0 > 0 && width > 0 ? Double(width) / Double($0) : nil } } ?? 16 / 9
        let width = ProfileGameGallery.supportedSize(364 * displayScale)
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "format", value: "webp"),
            URLQueryItem(name: "width", value: String(width)), URLQueryItem(name: "height", value: String(Int((Double(width) / ratio).rounded())))]
        return components.url
    }
}

struct ProfileGameDescription: View {
    let text: String
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    private var description: some View { Text(text).font(.system(size: 14)).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            description.lineLimit(expanded ? nil : 8).textSelection(.enabled)
                .background {
                    description.fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
                .background {
                    description.lineLimit(8).fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
                }
            if expanded || fullHeight > collapsedHeight + 1 {
                Button(expanded ? "Show Less" : "Show More") { expanded.toggle() }.buttonStyle(.plain).foregroundStyle(.tint)
            }
        }
    }
}
