import SakuraCordModels
import SwiftUI

struct ProfileGameDetails: View {
    let metadata: ProfileGameMetadata
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(spacing: 8) {
                if let steam = metadata.steamURL { website("Steam", url: steam) }
                ForEach(metadata.websites.filter { [16, 20, 21, 22, 23].contains($0.category) }) { site in
                    website(ProfileGameLabels.websites[site.category] ?? "Store", url: site.url)
                }
            }
            reviews
            VStack(alignment: .leading, spacing: 12) {
                Text("Details", bundle: #bundle).font(.headline)
                VStack(spacing: 0) {
                    detail("Genres", value: ProfileGameLabels.genres(metadata.genres))
                    detail("Publishers", value: metadata.publishers.joined(separator: ", "))
                    detail("Developer", value: metadata.developers.joined(separator: ", "))
                    if let date = metadata.releaseDate { detail("Release Date", value: date.formatted(date: .long, time: .omitted)) }
                    detail("Platforms", value: ProfileGameLabels.platforms(metadata.platforms))
                }
                .background(.primary.opacity(0.035), in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08)) }
            }
            HStack(spacing: 12) {
                ForEach(ProfileGameLabels.websiteOrder, id: \.self) { category in
                    if let site = metadata.websites.first(where: { $0.category == category }) {
                        Button { open(site.url) } label: {
                            Text(ProfileGameLabels.websites[category] ?? "Website").font(.caption)
                        }.buttonStyle(.plain).help(site.url.host ?? "")
                    }
                }
            }
        }
    }

    private func website(_ title: String, url: URL) -> some View {
        Button { open(url) } label: { Text(title).font(.system(size: 16, weight: .medium)).frame(maxWidth: .infinity).padding(10) }
            .buttonStyle(.plain).background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder private func detail(_ title: String, value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 20) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
            }.font(.system(size: 13)).padding(12)
            Divider().opacity(0.4)
        }
    }

    @ViewBuilder private var reviews: some View {
        if metadata.criticReviews != nil || metadata.steamURL != nil && !metadata.isRetiredFromSteam {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reviews", bundle: #bundle).font(.headline)
                VStack(spacing: 0) {
                    if let url = metadata.steamURL, !metadata.isRetiredFromSteam {
                        let steam = metadata.steamReviews
                        if let rating = steam?.recentRating, let count = steam?.recentCount, count >= 10 {
                            steamReview("Recent Reviews", rating: rating, count: count, recent: true, url: url)
                            Divider()
                        }
                        let localized = steam?.localizedRating != nil && (steam?.localizedCount ?? 0) >= 200 && (steam?.count ?? 0) >= 2000
                        steamReview(localized ? "English Reviews" : "All Reviews", rating: localized ? steam?.localizedRating : steam?.rating,
                                    count: localized ? steam?.localizedCount : steam?.count, recent: false, url: url)
                    }
                    if let critic = metadata.criticReviews {
                        Divider()
                        Button { open(critic.url) } label: {
                            HStack {
                                Text("OpenCritic")
                                Spacer()
                                Text(ProfileGameLabels.criticTiers[critic.tier] ?? "")
                                if critic.rating > 0, (critic.count ?? 0) > 0 {
                                    Text(Int(critic.rating.rounded(.down)).formatted()).monospacedDigit().fontWeight(.semibold)
                                        .frame(width: 30, height: 30).background(.tint.opacity(0.1), in: .circle)
                                }
                            }.font(.system(size: 13)).padding(12)
                        }.buttonStyle(.plain)
                    }
                }
                .background(.primary.opacity(0.035), in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08)) }
            }
        }
    }

    private func steamReview(_ title: String, rating: Double?, count: Int?, recent: Bool, url: URL) -> some View {
        Button { open(url) } label: {
            HStack {
                Text(title)
                Spacer()
                Text(ProfileGameLabels.steamRating(rating, count: count, recent: recent)).foregroundStyle(.tint)
                if let count, count >= 10 { Text("(\(count.formatted()))").foregroundStyle(.secondary) }
            }.font(.system(size: 12)).padding(12)
        }.buttonStyle(.plain)
    }
}

enum ProfileGameLabels {
    static let websiteOrder = [1, 4, 5, 8, 9, 19, 14, 6]
    static let websites = [
        1: "Website", 4: "Facebook", 5: "X", 6: "Twitch", 8: "Instagram", 9: "YouTube", 14: "Reddit",
        16: "Epic Games", 19: "Bluesky", 20: "Battle.net", 21: "Riot Games", 22: "Roblox", 23: "Minecraft"
    ]
    static let criticTiers = [1: "Mighty", 2: "Strong", 3: "Fair", 4: "Weak"]

    static func genres(_ values: [Int]) -> String { values.compactMap { genreNames[$0] }.joined(separator: ", ") }
    static func platforms(_ values: [Int]) -> String {
        let desktop = values.contains(0) || values.contains(6) || values.contains(7)
        return ([desktop ? "Desktop" : nil] + values.compactMap { [1: "Xbox", 2: "PlayStation", 5: "Nintendo"][$0] }).compactMap { $0 }.joined(separator: ", ")
    }

    static func steamRating(_ rating: Double?, count: Int?, recent: Bool) -> String {
        guard let rating, let count, count >= 10 else { return "No user reviews" }
        if rating >= 80 {
            if !recent, count < 50 { return "Positive" }
            return count < (recent ? 100 : 500) || rating < 95 ? "Very Positive" : "Overwhelmingly Positive"
        }
        if rating >= 70 { return "Mostly Positive" }
        if rating >= 40 { return "Mixed" }
        if rating >= 20 { return "Mostly Negative" }
        if !recent, count < 50 { return "Negative" }
        return count < (recent ? 100 : 500) ? "Very Negative" : "Overwhelmingly Negative"
    }

    private static let genreNames: [Int: String] = [
        1: "Action",
        2: "Action RPG",
        3: "Beat 'Em Up/Brawler",
        4: "Hack and Slash",
        5: "Platformer",
        6: "Stealth",
        7: "Survival",
        8: "Adventure",
        9: "Action-Adventure",
        10: "Metroidvania",
        11: "Open-world",
        12: "Psychological Horror",
        13: "Sandbox",
        14: "Survival Horror",
        15: "Visual Novel",
        16: "Driving/Racing",
        17: "Vehicular Combat",
        18: "Massively Multiplayer",
        19: "MMORPG",
        20: "Role-Playing",
        21: "Dungeon Crawler",
        22: "Roguelike",
        23: "Shooter",
        24: "Light-Gun",
        25: "Shoot 'Em Up",
        26: "FPS",
        27: "Dual-Joystick Shooter",
        28: "Simulation",
        29: "Flight Simulator",
        30: "Train Simulator",
        31: "Life Simulator",
        32: "Fishing",
        33: "Sports",
        34: "Baseball",
        35: "Basketball",
        36: "Billiards",
        37: "Bowling",
        38: "Boxing",
        39: "Football",
        40: "Golf",
        41: "Hockey",
        42: "Skateboarding/Skating",
        43: "Snowboarding/Skiing",
        44: "Football",
        45: "Athletics",
        46: "Surfing/Wakeboarding",
        47: "Wrestling",
        48: "Strategy",
        49: "4X",
        50: "Artillery",
        51: "RTS",
        52: "Tower Defence",
        53: "Turn-Based Strategy",
        54: "Wargame",
        55: "MOBA",
        56: "Fighting",
        57: "Puzzle",
        58: "Card Game",
        59: "Education",
        60: "Fitness",
        61: "Gambling",
        62: "Music/Rhythm",
        63: "Party/Mini-Game",
        64: "Pinball",
        65: "Trivia/Board Game",
        66: "Tactical",
        67: "Indie",
        68: "Arcade",
        69: "Point and Click",
    ]
}
