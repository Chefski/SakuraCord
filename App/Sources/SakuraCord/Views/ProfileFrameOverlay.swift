import SakuraCordModels
import SwiftUI

/// First-party frame layers use static asset URLs. Their three layout modes are
/// anchored staples, a clipped rail, and a vertically repeated border image.
struct ProfileFrameOverlay: View {
    let frame: ProfileFrame
    let order: String
    @State private var images: [String: CGImage] = [:]
    @State private var isSettled = false

    init(frame: ProfileFrame, order: String) {
        self.frame = frame
        self.order = order
        let cached = Self.cachedImages(frame: frame, order: order)
        _images = State(initialValue: cached)
        _isSettled = State(initialValue: cached.count == frame.layers.filter { $0.order == order }.count)
    }

    private static func cachedImages(frame: ProfileFrame, order: String) -> [String: CGImage] {
        var result: [String: CGImage] = [:]
        for layer in frame.layers where layer.order == order {
            result[layer.id] = AnimatedRemoteImageDisplayCache.shared.image(for: layer.staticURL, maximumPixelDimension: 2048)?.frames.first
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / max(1, frame.innerWidth)
            let overflowX = frame.overflowHorizontal * scale
            let overflowTop = frame.overflowTop * scale
            let overflowBottom = frame.overflowBottom * scale
            Canvas { context, size in
                guard isSettled else { return }
                let content = CGRect(x: 0, y: overflowTop, width: size.width, height: geometry.size.height)
                for layer in frame.layers where layer.order == order {
                    guard let image = images[layer.id], image.width > 0 else { continue }
                    let height = size.width * CGFloat(image.height) / CGFloat(image.width)
                    guard height > 0 else { continue }
                    let resolved = context.resolve(Image(decorative: image, scale: 1))
                    switch layer.type {
                    case "staple":
                        let originY = layer.anchor == "bottom" ? size.height - height : 0
                        context.draw(resolved, in: CGRect(x: 0, y: originY, width: size.width, height: height))
                    case "rail":
                        guard !layer.isResponsive || geometry.size.width / max(1, geometry.size.height) < 300.0 / 480 else { continue }
                        var clipped = context
                        clipped.clip(to: Path(content))
                        let originY: CGFloat
                        switch layer.anchor {
                        case "bottom": originY = content.maxY - height
                        case "center": originY = content.midY - height / 2
                        default: originY = content.minY
                        }
                        clipped.draw(resolved, in: CGRect(x: 0, y: originY, width: size.width, height: height))
                    case "border":
                        var clipped = context
                        clipped.clip(to: Path(content))
                        for originY in stride(from: content.minY, to: content.maxY, by: height) {
                            clipped.draw(resolved, in: CGRect(x: 0, y: originY, width: size.width, height: height))
                        }
                    default: break
                    }
                }
            }
            .frame(width: geometry.size.width + overflowX * 2,
                   height: geometry.size.height + overflowTop + overflowBottom)
            .offset(x: -overflowX, y: -overflowTop)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: frame) {
            images = Self.cachedImages(frame: frame, order: order)
            let layers = frame.layers.filter { $0.order == order }
            isSettled = images.count == layers.count
            guard !isSettled else { return }
            let loaded = await withTaskGroup(of: (String, DecodedAnimatedImage?).self) { group in
                for layer in layers {
                    group.addTask {
                        let image = try? await SharedAnimatedImageLoader.shared.image(for: layer.staticURL, maximumPixelDimension: 2048)
                        if let image, !Task.isCancelled {
                            await AnimatedRemoteImageDisplayCache.shared.insert(image, for: layer.staticURL, maximumPixelDimension: 2048)
                        }
                        return (layer.id, image)
                    }
                }
                var result: [String: CGImage] = [:]
                for await (id, image) in group { result[id] = image?.frames.first }
                return result
            }
            guard !Task.isCancelled else { return }
            images = loaded
            isSettled = true
        }
    }
}
