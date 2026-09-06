import MediaPipeline
import SwiftUI

struct ProfileImageCropView: View {
    let image: ProfileImageSource
    let imageURL: URL
    let filename: String
    let purpose: ProfileImagePurpose
    let isProcessing: Bool
    let canApply: Bool
    let cancel: () -> Void
    let apply: (ProfileImageCropGeometry) -> Void

    @State private var geometry: ProfileImageCropGeometry
    @State private var dragOrigin: CGPoint?
    private enum Control: Hashable { case crop, zoom }
    @FocusState private var focusedControl: Control?
    @Environment(\.profileEditorModal) private var modal

    init(image: ProfileImageSource, imageURL: URL, filename: String, purpose: ProfileImagePurpose,
         isProcessing: Bool, canApply: Bool, aspectRatio: Double? = nil, initialGeometry: ProfileImageCropGeometry? = nil,
         cancel: @escaping () -> Void, apply: @escaping (ProfileImageCropGeometry) -> Void) {
        self.image = image; self.imageURL = imageURL; self.filename = filename; self.purpose = purpose
        self.isProcessing = isProcessing; self.cancel = cancel; self.apply = apply
        self.canApply = canApply
        _geometry = State(initialValue: initialGeometry ?? ProfileImageCropGeometry(naturalSize: image.size, purpose: purpose, aspectRatio: aspectRatio))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Image", bundle: #bundle).font(.title2.bold())
                Spacer()
                HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close", action: cancel)
            }
            .padding(24)
            cropViewport
                .padding(.horizontal, 24)
            HStack(spacing: 8) {
                Spacer()
                Image(systemName: "photo").font(.caption).accessibilityHidden(true)
                Slider(value: Binding(get: { geometry.zoom }, set: { geometry.setZoom($0) }), in: 1 ... 2, step: 0.025,
                       onEditingChanged: { if $0 { focusedControl = .zoom } })
                    .frame(width: 128)
                    .accessibilityLabel("Zoom")
                    .accessibilityValue("\(Int(geometry.zoom * 100)) percent")
                    .focusable(interactions: .edit)
                    .focused($focusedControl, equals: .zoom)
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                        guard !isProcessing else { return .handled }
                        let increases = press.key == .rightArrow || press.key == .upArrow
                        geometry.setZoom(geometry.zoom + (increases ? 0.025 : -0.025))
                        return .handled
                    }
                Image(systemName: "photo").font(.title2).accessibilityHidden(true)
                Spacer()
                Button("Rotate Clockwise", systemImage: "rotate.right") { geometry.rotate() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.title2)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .disabled(isProcessing)
            Divider()
            if !canApply {
                Label("This profile image requires Nitro.", systemImage: "sparkles")
                    .font(.callout).padding(.top, 16)
            }
            HStack {
                Button("Reset") { geometry.reset() }.disabled(!geometry.hasEdits || isProcessing)
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button { apply(geometry) } label: {
                    if isProcessing { ProgressView().controlSize(.small) } else { Text("Apply", bundle: #bundle) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !canApply)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(24)
        }
        .profileEditorModalSize(width: 480)
        .defaultFocus($focusedControl, .crop)
        .onAppear { modal?.animationState.escapeAction = cancel }
        .onDisappear { modal?.animationState.escapeAction = nil }
    }

    private var cropViewport: some View {
        ZStack {
            Color.black
            AnimatedRemoteImage(url: imageURL, animates: image.isAnimated, contentMode: .fit)
                .frame(width: geometry.displayedUnrotatedSize.width, height: geometry.displayedUnrotatedSize.height)
                .rotationEffect(.degrees(Double(geometry.quarterTurns * 90)))
                .offset(x: geometry.offset.x, y: geometry.offset.y)
            Rectangle().fill(.black.opacity(0.55))
                .reverseMask {
                    cropShape.fill(.white).frame(width: geometry.cropSize.width, height: geometry.cropSize.height)
                }
                .allowsHitTesting(false)
            cropShape.stroke(.white, lineWidth: 5)
                .frame(width: geometry.cropSize.width, height: geometry.cropSize.height)
                .allowsHitTesting(false)
        }
        .frame(height: 350)
        .clipped()
        .clipShape(ConcentricRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            focusedControl = .crop
            if dragOrigin == nil { dragOrigin = geometry.offset }
            let initial = dragOrigin ?? .zero
            geometry.setOffset(CGPoint(x: initial.x + value.translation.width, y: initial.y + value.translation.height))
        }.onEnded { _ in dragOrigin = nil })
        .simultaneousGesture(TapGesture().onEnded { focusedControl = .crop })
        .focusable(interactions: .edit)
        .focused($focusedControl, equals: .crop)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard !isProcessing else { return .handled }
            let step: CGFloat = press.modifiers.contains(.shift) ? 40 : 4
            var offset = geometry.offset
            switch press.key {
            case .leftArrow: offset.x -= step
            case .rightArrow: offset.x += step
            case .upArrow: offset.y -= step
            case .downArrow: offset.y += step
            default: break
            }
            geometry.setOffset(offset)
            return .handled
        }
        .disabled(isProcessing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crop \(filename)")
        .accessibilityHint("Use the arrow keys to move the image. Hold Shift to move farther.")
    }

    private var cropShape: UnevenRoundedRectangle {
        let radius = purpose == .avatar ? min(geometry.cropSize.width, geometry.cropSize.height) / 2 : purpose == .widgetField ? geometry.cropSize.width / 6 : 0
        return UnevenRoundedRectangle(cornerRadii: .init(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius))
    }
}

private extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask { Rectangle().overlay { mask().blendMode(.destinationOut) }.compositingGroup() }
    }
}
