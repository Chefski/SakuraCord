import SakuraCordModels
import SwiftUI

struct ProfileEffectOverlay: View {
    let effect: ProfileEffect
    let animates: Bool
    var maximumPixelDimension: Int?
    var idlePreviewURL: URL?
    var restartsOnHover = false

    private struct LoadRequest: Hashable {
        let animations: [ProfileEffectAnimation]
        let maximumPixelDimension: Int?
        let fallbackURL: URL?
    }

    @State private var loadedAnimations: [ProfileEffectAnimation]?
    @State private var loadedImages: [URL: DecodedAnimatedImage] = [:]
    @State private var pendingSources: Set<URL> = []
    @State private var playbackClock = AnimatedImagePlaybackClock()
    @State private var startTime: CFTimeInterval?

    init(effect: ProfileEffect, animates: Bool, maximumPixelDimension: Int? = nil, idlePreviewURL: URL? = nil, restartsOnHover: Bool = false) {
        self.effect = effect
        self.animates = animates
        self.maximumPixelDimension = maximumPixelDimension
        self.idlePreviewURL = idlePreviewURL
        self.restartsOnHover = restartsOnHover
        let images = Self.cachedImages(effect: effect, maximumPixelDimension: maximumPixelDimension)
        let pending = Set(effect.animations.map(\.sourceURL)).subtracting(images.keys)
        _loadedAnimations = State(initialValue: effect.animations)
        _loadedImages = State(initialValue: images)
        _pendingSources = State(initialValue: pending)
        let firstStart = effect.animations.map(\.startMilliseconds).min() ?? 0
        let ready = !images.isEmpty && effect.animations.filter { $0.startMilliseconds == firstStart }.allSatisfy { !pending.contains($0.sourceURL) }
        _startTime = State(initialValue: animates && ready ? CACurrentMediaTime() : nil)
    }

    private static func cachedImages(effect: ProfileEffect, maximumPixelDimension: Int?) -> [URL: DecodedAnimatedImage] {
        var images: [URL: DecodedAnimatedImage] = [:]
        let sources = Set(effect.animations.map(\.sourceURL) + [effect.reducedMotionURL].compactMap { $0 })
        for url in sources {
            images[url] = AnimatedRemoteImageDisplayCache.shared.image(for: url, maximumPixelDimension: maximumPixelDimension)
        }
        return images
    }

    var body: some View {
        GeometryReader { proxy in
            if !effect.animations.isEmpty {
                let designWidth = ProfileEffectLayout.designWidth(for: effect.animations)
                ZStack(alignment: .topLeading) {
                    ForEach(loadedAnimations == effect.animations ? effect.animations.filter {
                        loadedImages[$0.sourceURL] != nil
                    } : []) { animation in
                        let frame = ProfileEffectLayout.frame(
                            for: animation,
                            designWidth: designWidth,
                            containerWidth: proxy.size.width
                        )
                        AnimatedRemoteImage(
                            url: animation.sourceURL,
                            animates: animates && startTime != nil,
                            isLooping: animation.isLooping,
                            playback: startTime.map {
                                AnimatedImagePlayback(
                                    startTime: $0 + Double(animation.startMilliseconds) / 1_000,
                                    clock: playbackClock,
                                    duration: Double(animation.durationMilliseconds) / 1_000,
                                    loopDelay: Double(animation.loopDelayMilliseconds) / 1_000
                                )
                            },
                            loadedImage: loadedImages[animation.sourceURL],
                            maximumPixelDimension: maximumPixelDimension,
                            accessibilityCategory: .decoration
                        )
                            .frame(
                                width: frame.width,
                                height: frame.height
                            )
                            .offset(
                                x: frame.minX,
                                y: frame.minY
                            )
                            .zIndex(Double(animation.zIndex))
                    }
                }
                .opacity(startTime == nil ? 0 : 1)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            } else if let url = effect.reducedMotionURL, let image = loadedImages[url] {
                AnimatedRemoteImage(
                    url: url,
                    animates: animates,
                    playback: startTime.map { AnimatedImagePlayback(startTime: $0, clock: playbackClock, duration: 0, loopDelay: 0) },
                    loadedImage: image,
                    maximumPixelDimension: maximumPixelDimension,
                    accessibilityCategory: .decoration
                )
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else if let url = effect.staticURL {
                AnimatedRemoteImage(url: url, animates: false, maximumPixelDimension: maximumPixelDimension)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .opacity(showsIdlePreview ? 0 : 1)
        .overlay {
            if let idlePreviewURL {
                // Keep the preview loaded, but never composite it with the effect's transparent layers.
                AnimatedRemoteImage(url: idlePreviewURL, animates: false, contentMode: .fill)
                    .opacity(showsIdlePreview ? 1 : 0)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityLabel(effect.accessibilityLabel ?? "Profile effect")
        .task(id: LoadRequest(animations: effect.animations, maximumPixelDimension: maximumPixelDimension, fallbackURL: effect.reducedMotionURL)) {
            if loadedAnimations != effect.animations {
                startTime = nil
                playbackClock = AnimatedImagePlaybackClock()
            }
            loadedAnimations = effect.animations
            loadedImages = Self.cachedImages(effect: effect, maximumPixelDimension: maximumPixelDimension)
            pendingSources = Set(effect.animations.map(\.sourceURL)).subtracting(loadedImages.keys)
            startIfReady()
            if effect.animations.isEmpty, let url = effect.reducedMotionURL, loadedImages[url] == nil {
                let image = try? await SharedAnimatedImageLoader.shared.image(for: url, maximumPixelDimension: maximumPixelDimension)
                guard !Task.isCancelled else { return }
                cache(image, for: url)
                loadedImages[url] = image
                startIfReady()
            }
            // Decode in presentation order: the shared decoder is serial,
            // so submitting passive layers first would hold up the intro.
            // Later layers join the opening layers' existing clock.
            let starts = Set(effect.animations.map(\.startMilliseconds)).sorted()
            for start in starts {
                guard !Task.isCancelled else { return }
                let sources = Set(effect.animations.filter {
                    $0.startMilliseconds == start
                }.map(\.sourceURL)).intersection(pendingSources)
                await withTaskGroup(of: (URL, DecodedAnimatedImage?).self) { group in
                    for url in sources {
                        group.addTask {
                            let image = try? await SharedAnimatedImageLoader.shared.image(
                                for: url, maximumPixelDimension: maximumPixelDimension
                            )
                            return (url, image)
                        }
                    }
                    for await (url, image) in group {
                        guard !Task.isCancelled else { return }
                        cache(image, for: url)
                        loadedImages[url] = image
                        pendingSources.remove(url)
                        startIfReady()
                    }
                }
            }
        }
        .onChange(of: animates) { _, _ in
            if restartsOnHover {
                // Reset on hover exit as well as entry, retaining decoded frames and mounted image views.
                playbackClock = AnimatedImagePlaybackClock()
                startTime = nil
            }
            startIfReady()
        }
        .onDisappear {
            startTime = nil
            loadedAnimations = nil
            loadedImages = [:]
            pendingSources = []
        }
    }

    private func cache(_ image: DecodedAnimatedImage?, for url: URL) {
        guard let image else { return }
        AnimatedRemoteImageDisplayCache.shared.insert(image, for: url, maximumPixelDimension: maximumPixelDimension)
    }

    private var showsIdlePreview: Bool {
        idlePreviewURL != nil && (!animates || startTime == nil)
    }

    private func startIfReady() {
        guard animates, startTime == nil, loadedAnimations == effect.animations else { return }
        guard !loadedImages.isEmpty else { return }
        let firstStart = effect.animations.map(\.startMilliseconds).min() ?? 0
        guard effect.animations.filter({ $0.startMilliseconds <= firstStart }).allSatisfy({
            !pendingSources.contains($0.sourceURL)
        }) else { return }
        startTime = CACurrentMediaTime()
    }
}
