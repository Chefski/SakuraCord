import MetalKit
import OSLog
import SwiftUI

final class SakuraCordWelcomeMetalView: MTKView {
    private struct Uniforms {
        var viewport = SIMD4<Float>(0, 0, 0, 1)
        var atlas = SIMD4<Float>(0, 0, Float(SakuraCordWelcomePetalAtlas.cellSize), 1)
        var first = SIMD4<Float>(1, 0.5, 0.7, 1)
        var last = SIMD4<Float>(0.7, 0.5, 1, 1)
        var ink = SIMD4<Float>(1, 1, 1, 1)
    }

    private var uniforms = Uniforms()
    private var commandQueue: (any MTLCommandQueue)?
    private var pipeline: (any MTLRenderPipelineState)?
    private var petalAtlas: SakuraCordWelcomePetalAtlas?

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        isPaused = true
        enableSetNeedsDisplay = true
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        colorPixelFormat = .bgra8Unorm
        wantsLayer = true
        layer?.isOpaque = false
        guard let device else { return }
        do {
            let library = try device.makeDefaultLibrary(bundle: .module)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "SakuraCord petal fusion"
            descriptor.vertexFunction = library.makeFunction(name: "sakuraPetalVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "sakuraPetalFragment")
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = colorPixelFormat
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            commandQueue = device.makeCommandQueue()
            petalAtlas = SakuraCordWelcomePetalAtlas(device: device)
        } catch {
            Logger(subsystem: "dev.sakuracord.SakuraCord", category: "Welcome")
                .error("Could not prepare petal renderer: \(error.localizedDescription, privacy: .public)")
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }

    func update(progress: Double, first: Color, last: Color, isDark: Bool) {
        uniforms.viewport.z = Float(progress)
        uniforms.atlas.w = isDark ? 1 : 0
        uniforms.first = components(first)
        uniforms.last = components(last)
        uniforms.ink = isDark ? SIMD4(0.96, 0.95, 0.98, 1) : SIMD4(0.18, 0.12, 0.22, 1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0,
              let petalAtlas, let pipeline, let commandQueue,
              let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let command = commandQueue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }
        uniforms.viewport.x = Float(bounds.width)
        uniforms.viewport.y = Float(bounds.height)
        uniforms.viewport.w = Float(min(1, bounds.width * 0.112 / SakuraCordWelcomePetalAtlas.fontSize))
        uniforms.atlas.x = petalAtlas.size.x
        uniforms.atlas.y = petalAtlas.size.y
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(petalAtlas.petals, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(petalAtlas.mask, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: petalAtlas.count)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private func components(_ color: Color) -> SIMD4<Float> {
        let color = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return SIMD4(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), 1)
    }
}
