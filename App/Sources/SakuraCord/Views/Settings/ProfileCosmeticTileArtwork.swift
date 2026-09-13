import SakuraCordModels
import SwiftUI

/// The same miniature profile composition is used by controls and inventory grids.
struct ProfileCosmeticTileArtwork: View {
    var effect: ProfileEffect?
    var frame: ProfileFrame?
    let kind: ProfileCollectibleKind
    var fillsTile = false
    var animates = false
    @State private var hasStartedAnimation = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let width = fillsTile ? geometry.size.width : geometry.size.width * 0.56
            let height = fillsTile ? geometry.size.height : geometry.size.height * 0.8
            miniature
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: fillsTile ? 0 : 8))
                .background { if let frame { ProfileFrameOverlay(frame: frame, order: "back") } }
                .overlay { if let frame { ProfileFrameOverlay(frame: frame, order: "front") } }
                .overlay {
                    if kind == .frame, frame == nil {
                        RoundedRectangle(cornerRadius: 15).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [1, 3]))
                            .padding(-7)
                    }
                }
                .overlay {
                    if kind == .frame ? frame == nil : effect == nil {
                        Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(.black.opacity(0.16))
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: animates, initial: true) { _, playing in if playing { hasStartedAnimation = true } }
        .onChange(of: effect) { _, _ in hasStartedAnimation = false }
    }

    private var miniature: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.35)
                Rectangle().fill(.white.opacity(0.06)).frame(height: geometry.size.height * 0.35)
                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: geometry.size.width * 0.25))
                        .padding(.bottom, 2)
                    ForEach([0.5, 0.76, 0.64, 0.3, 0.88], id: \.self) { fraction in
                        Capsule().frame(width: geometry.size.width * fraction, height: 4)
                    }
                }
                .foregroundStyle(.white.opacity(0.18))
                .padding(geometry.size.width * 0.08)
                .padding(.top, geometry.size.height * 0.2)
                if let effect {
                    if animates || hasStartedAnimation || (effect.thumbnailURL == nil && effect.staticURL == nil) {
                        ProfileEffectOverlay(
                            effect: effect, animates: animates,
                            maximumPixelDimension: max(1, Int((max(geometry.size.width, geometry.size.height) * displayScale).rounded(.up))),
                            idlePreviewURL: effect.thumbnailURL ?? effect.staticURL,
                            restartsOnHover: true
                        )
                    } else if let url = effect.thumbnailURL ?? effect.staticURL {
                        ProfileEffectPreviewImage(url: url)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}
