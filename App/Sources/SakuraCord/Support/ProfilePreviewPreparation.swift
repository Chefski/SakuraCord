import AppKit
import SakuraCordModels

/// Warm only the current profile's visible artwork, using the same bounded caches as its views.
@MainActor
enum ProfilePreviewPreparation {
    static func preload(_ profile: UserProfile) async {
        await withTaskGroup(of: Void.self) { group in
            var sources = Set(profile.effect?.animations.map(\.sourceURL) ?? [])
            sources.formUnion([profile.effect?.reducedMotionURL, profile.effect?.staticURL, profile.effect?.thumbnailURL, profile.bannerURL].compactMap { $0 })
            for url in sources {
                group.addTask { await preload(url, maximumPixelDimension: nil) }
            }
            if let url = profile.user.nameplate?.staticURL {
                group.addTask { await preload(url, maximumPixelDimension: 512) }
            }
            // Match the hero and customization-card avatar renderers' cache keys.
            for size in [CGFloat(70), CGFloat(80)] {
                if let url = profile.avatarURL {
                    let pixels = AvatarView(name: "", url: url, size: size).requestedPixelDimension
                    group.addTask { await preloadAvatar(url, maximumPixelDimension: pixels) }
                }
                if let url = profile.user.avatarDecorationURL {
                    let pixels = DecoratedAvatarView(name: "", avatarURL: nil, decorationURL: url, size: size).decorationPixelDimension
                    group.addTask { await preload(url, maximumPixelDimension: pixels) }
                }
            }
            for layer in profile.frame?.layers ?? [] {
                group.addTask { await preload(layer.staticURL, maximumPixelDimension: 2048) }
            }
            let theme = ProfileThemeState()
            await theme.load(theme.source(for: profile, scale: NSScreen.main?.backingScaleFactor ?? 2, isPreview: true))
        }
    }

    private static func preloadAvatar(_ url: URL, maximumPixelDimension: Int) async {
        guard !Task.isCancelled else { return }
        if NativeTimelineAvatarPresentation.shouldDecodeAnimation(for: url) {
            await preload(url, maximumPixelDimension: maximumPixelDimension)
        } else {
            _ = await SharedDecodedImageLoader.shared.image(for: url, maximumPixelDimension: maximumPixelDimension, priority: .prefetch)
        }
    }

    private static func preload(_ url: URL, maximumPixelDimension: Int?) async {
        guard !Task.isCancelled,
              let image = try? await SharedAnimatedImageLoader.shared.image(for: url, maximumPixelDimension: maximumPixelDimension),
              !Task.isCancelled else { return }
        AnimatedRemoteImageDisplayCache.shared.insert(image, for: url, maximumPixelDimension: maximumPixelDimension)
    }
}
