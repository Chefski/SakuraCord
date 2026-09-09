import SakuraCordModels
import SwiftUI

struct ProfileEffectOverlay: View {
    let effect: ProfileEffect
    let animates: Bool

    @State private var loadedAnimations: [ProfileEffectAnimation]?
    @State private var loadedImages: [URL: DecodedAnimatedImage] = [:]
    @State private var pendingSources: Set<URL> = []
    @State private var playbackClock = AnimatedImagePlaybackClock()
    @State private var startTime: CFTimeInterval?

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
            } else if let url = effect.reducedMotionURL {
                AnimatedRemoteImage(
                    url: url,
                    animates: animates,
                    accessibilityCategory: .decoration
                )
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else if let url = effect.staticURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityLabel(effect.accessibilityLabel ?? "Profile effect")
        .task(id: effect.animations) {
            startTime = nil
            playbackClock = AnimatedImagePlaybackClock()
            loadedAnimations = effect.animations
            loadedImages = [:]
            pendingSources = Set(effect.animations.map(\.sourceURL))
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
                                for: url, maximumPixelDimension: nil
                            )
                            return (url, image)
                        }
                    }
                    for await (url, image) in group {
                        guard !Task.isCancelled else { return }
                        loadedImages[url] = image
                        pendingSources.remove(url)
                        startIfReady()
                    }
                }
            }
        }
        .onChange(of: animates) { _, _ in startIfReady() }
        .onDisappear {
            startTime = nil
            loadedAnimations = nil
            loadedImages = [:]
            pendingSources = []
        }
    }

    private func startIfReady() {
        guard animates, startTime == nil, loadedAnimations == effect.animations else { return }
        let firstStart = effect.animations.map(\.startMilliseconds).min() ?? 0
        guard effect.animations.filter({ $0.startMilliseconds <= firstStart }).allSatisfy({
            !pendingSources.contains($0.sourceURL)
        }) else { return }
        startTime = CACurrentMediaTime()
    }
}
