import SakuraCordModels

enum SakuraCordSponsors {
    private static let githubAccountIDs: Set<String> = [
        "57096215", // TheDutchSmoke
        "14123121", // charlie-hotel
        "143897379" // super-original — temporary badge testing
    ]

    static let badge = ProfileBadge(id: "sakuracord_sponsor", description: "SakuraCord Sponsor")

    static func badges(for profile: UserProfile) -> [ProfileBadge] {
        let isSponsor = profile.connectedAccounts.contains { account in
            account.type == "github" && account.isVerified && githubAccountIDs.contains(account.accountID)
        }
        return isSponsor ? [badge] + profile.badges : profile.badges
    }
}
