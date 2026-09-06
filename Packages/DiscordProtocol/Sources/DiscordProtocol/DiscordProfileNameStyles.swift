import Foundation
import SakuraCordModels

/// First-party profile style configuration, stable 607562, observed 5 September
/// 2026. Font assets are loaded from their captured immutable URLs at runtime.
/// Dormant font/effect IDs from the bundle are intentionally not picker options.
public enum DiscordProfileNameStyles {
    public static func defaultColors(for effect: ProfileNameEffect, darkAppearance: Bool) -> [UInt32] {
        switch effect {
        case .solid: [darkAppearance ? 0xD4D5D8 : 0x2E2E34]
        case .gradient: catalog.gradients[0]
        case .neon: [6_888_941]
        case .toon: [0xF42098]
        case .pop: [1_036_166]
        case .gummy: catalog.gummyPalettes[0]
        case .prism: catalog.prismPalettes[0]
        }
    }

    public static let catalog = ProfileNameStyleCatalog(
        fonts: [
            font(11, "gg sans", "ggsans-Bold", "189422196a4f8b53"),
            font(12, "Tempo", "Tempo-Semibold", "27b34a77ba5d693e", spacing: 0.03),
            font(3, "Sakura", "Sakura-Normal", "33d4f12a85e1f736", spacing: 0.04),
            font(4, "Jellybean", "Jellybean-Normal", "e6f5f44abb520735"),
            font(6, "Modern", "Modern-Medium", "c560709c3470bb66", spacing: 0.01),
            font(7, "Medieval", "Medieval-Normal", "52b541f86401a5b6", spacing: 0.02),
            font(8, "8Bit", "8Bit-Normal", "69c735ca5c604de7", spacing: 0.02),
            font(10, "Vampyre", "Vampyre-Normal", "8f20cb550d739cea", spacing: 0.01),
            font(13, "Monkey Bars", "MonkeyBars-Bold", "45ef50dce38a931a", isNew: true),
            font(14, "Mainframe", "Mainframe-Bold", "4841dace333e9054", spacing: 0.03, isNew: true),
            font(15, "Headbang", "Headbang-Normal", "c00df4f25667809b", isNew: true),
            font(16, "Journal", "Journal-Bold", "aa59ae54ce7e540a", isNew: true),
        ],
        solidColors: [
            1628845, 2417517, 1874155, 12790527, 16521573, 13018645,
            695675, 1027403, 747943, 11080677, 14287177, 16332578,
        ],
        gradients: [
            [2797222, 16762000], [2535780, 9497343], [14966527, 2522592], [9452762, 2939534],
            [15709354, 14970082], [14631474, 12423167], [16095292, 15031015], [14963742, 6674404],
        ],
        gummyPalettes: [
            [15313365, 11132400, 12167150, 12184267], [16740290, 16076712, 16751574, 14248631],
            [16758138, 16749423, 16743544, 15756170], [12905829, 10018400, 7130467, 4570214],
            [8173823, 9363664, 10327285, 6737904], [14121983, 11889663, 14965989, 9137407],
        ],
        prismPalettes: [
            [16683586, 3534206, 16769095, 16731346, 5793266],
            [16727357, 16747050, 16766023, 16732067, 8086015],
            [7997702, 13114898, 16013848, 16749824, 16766023],
            [8316888, 8178687, 8359167, 11890175, 15960792],
            [3528287, 1497266, 2147829, 2850047, 7032319],
            [11004065, 14282892, 16769162, 16762024, 15972057],
        ]
    )

    private static func font(
        _ id: Int, _ name: String, _ postScriptName: String, _ hash: String,
        spacing: Double = 0, isNew: Bool = false
    ) -> ProfileNameFont {
        ProfileNameFont(
            id: id, name: name, postScriptName: postScriptName,
            assetURL: URL(string: "https://discord.com/assets/\(hash).woff2"), letterSpacing: spacing, isNew: isNew
        )
    }
}
