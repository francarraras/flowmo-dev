import Metal
import QuartzCore
import SwiftUI

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

/// The Distant Horizon shader, compiled from this source at first use with
/// `MTLDevice.makeLibrary(source:)`. Keeping it as a string means the same
/// bytes ship through `swift build`, Xcode, and both phone hosts, with no Metal
/// toolchain at build time and no binary library to track in provenance.
enum HorizonShaderSource {
    static let source = #"""
        #include <metal_stdlib>
        using namespace metal;

        struct HorizonUniforms {
            float2 size;
            float time;
            float light;
            float warmth;
            float turn;
            float travel;
            float arcY;
            float grain;
            float shimmer;
            float relief;
            float curvature;
            float pixel;
            float haze;
            float stars;
            float meteorT;
            float meteorSeed;
        };

        // ---------- noise ----------

        static float hash21(float2 p) {
            p = fract(p * float2(123.34, 456.21));
            p += dot(p, p + 45.32);
            return fract(p.x * p.y);
        }

        static float vnoise(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);
            float2 u = f * f * (3.0 - 2.0 * f);
            float a = hash21(i);
            float b = hash21(i + float2(1.0, 0.0));
            float c = hash21(i + float2(0.0, 1.0));
            float d = hash21(i + float2(1.0, 1.0));
            return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
        }

        static float fbm(float2 p) {
            float v = 0.0;
            float a = 0.5;
            for (int i = 0; i < 4; i++) {
                v += a * vnoise(p);
                p = p * 2.03 + float2(17.1, 9.2);
                a *= 0.5;
            }
            return v;
        }

        // ---------- palette (Look.swift tokens) ----------

        constant float3 kField = float3(9.0, 10.0, 12.0) / 255.0;
        constant float3 kInk = float3(243.0, 241.0, 234.0) / 255.0;
        constant float3 kRest = float3(214.0, 184.0, 137.0) / 255.0;
        constant float3 kRestDeep = float3(132.0, 110.0, 78.0) / 255.0;
        constant float3 kCool = float3(150.0, 154.0, 162.0) / 255.0;

        // ---------- horizon ----------
        //
        // A vast dark sphere fills the lower canvas; the camera sits just above its
        // surface looking at the limb. The light is *below* the horizon, so what we
        // see is dawn: a luminous atmosphere along the limb, grazing light on the
        // terrain nearest it, aerial haze where the far surface melts into that
        // atmosphere, and darkness above for the header.

        struct Dawn {
            float along;
            float3 glow;
            float3 deep;
            float cx;
        };

        static float starField(float2 position, constant HorizonUniforms& u) {
            if (u.stars <= 0.0) return 0.0;
            float cell = 44.0;
            float2 g = floor(position / cell);
            float2 f = fract(position / cell);
            if (hash21(g) > u.stars) return 0.0;
            float2 starPos = float2(hash21(g + 1.3), hash21(g + 7.7)) * 0.8 + 0.1;
            float dist = length((f - starPos) * cell);
            float radius = (0.55 + 0.75 * hash21(g + 3.3)) * max(1.0, u.pixel * 2.0);
            float core = exp(-(dist * dist) / (2.0 * radius * radius));
            float brightness = 0.25 + 0.75 * hash21(g + 5.1);
            float phase = hash21(g + 9.9) * 6.2831;
            float rate = 0.20 + 0.35 * hash21(g + 2.2);
            float drift = 1.0 - 0.40 * u.shimmer * (0.5 + 0.5 * sin(u.time * rate + phase));
            return core * brightness * drift;
        }

        static float meteor(float2 position, constant HorizonUniforms& u) {
            if (u.meteorT < 0.0 || u.meteorT > 1.4) return 0.0;
            float s1 = hash21(float2(u.meteorSeed, 1.0));
            float s2 = hash21(float2(u.meteorSeed, 2.0));
            float dirX = s1 > 0.5 ? 1.0 : -1.0;
            float2 start = float2(u.size.x * (0.20 + 0.60 * s2), u.size.y * (0.08 + 0.20 * s1));
            float2 dir = normalize(float2(dirX, 0.28 + 0.30 * s2));
            float len = u.size.x * 0.14;
            float2 head = start + dir * (len / 0.85) * u.meteorT;
            float2 tail = head - dir * len * 0.55;
            float2 pa = position - tail;
            float2 ba = head - tail;
            float along = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float dseg = length(pa - ba * along);
            float width = 0.9 * max(1.0, u.pixel * 2.0);
            float fade = smoothstep(0.0, 0.10, u.meteorT) * smoothstep(1.4, 0.75, u.meteorT);
            return exp(-(dseg * dseg) / (2.0 * width * width)) * along * along * fade;
        }

        static float3 skyColor(float sdf, float2 position, constant HorizonUniforms& u, Dawn dawn) {
            float minSide = min(u.size.x, u.size.y);
            float light = u.light;
            float h = max(0.0, sdf) / minSide;

            float band = exp(-h * mix(70.0, 12.0, light));
            float upper = exp(-h * mix(24.0, 5.0, light)) * (0.10 + 0.32 * light);
            float3 col = kField;
            float skyLight = clamp(dawn.along * (band * (0.40 + 0.95 * light) + upper * 2.0), 0.0, 1.0);
            float starVis = (1.0 - skyLight) * (1.0 - 0.6 * light * dawn.along);
            col += kInk * starField(position, u) * 0.55 * starVis;
            col += kInk * meteor(position, u) * 0.75 * (1.0 - skyLight);
            col += dawn.glow * dawn.along * band * (0.40 + 0.95 * light);
            col += mix(dawn.glow, kCool, 0.55) * dawn.along * upper;
            col += dawn.deep * dawn.along * light * exp(-h * 30.0) * 0.30;
            float sigma = 0.9 + 2.6 * light;
            float limbLine = exp(-(sdf * sdf) / (2.0 * sigma * sigma));
            col += mix(dawn.glow, float3(1.0), 0.12) * limbLine * dawn.along * (0.45 + 0.75 * light);
            return col;
        }

        static float3 surfaceColor(float sdf, float2 d, float R, float2 position, constant HorizonUniforms& u, Dawn dawn) {
            float minSide = min(u.size.x, u.size.y);
            float light = u.light;
            float dist = length(d);
            float z = sqrt(max(0.0, R * R - dist * dist));
            float3 n = normalize(float3(d.x, d.y, z));
            float depth = max(0.0, -sdf) / minSide;

            float lon = atan2(d.x, z) + u.turn;
            float lat = asin(clamp(d.y / R, -1.0, 1.0));
            float2 sp = float2(lon * 4.5, lat * 30.0);
            float ridge = fbm(sp);
            float fine = fbm(sp * 2.9 + 11.0);
            float relief = ridge * 0.8 + fine * 0.2;
            float e = 0.03;
            float rx = fbm(sp + float2(e, 0.0)) - ridge;
            float ry = fbm(sp + float2(0.0, e)) - ridge;
            float2 ldir = normalize(float2((dawn.cx - position.x) / u.size.x, -1.0));
            float facing = clamp(0.5 + u.relief * 10.0 * (rx * ldir.x + ry * ldir.y), 0.0, 1.0);

            float3 L = normalize(float3((dawn.cx - position.x) / u.size.x * 0.6, -1.0, 0.42));
            float lambert = max(0.0, dot(n, L));
            float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.0);
            float grazing = exp(-depth * mix(22.0, 8.0, light)) * dawn.along * light;

            float3 obsidian = float3(0.036, 0.039, 0.046);
            float3 col = obsidian * (0.85 + 0.6 * u.relief * (relief - 0.5));
            col *= 0.5 + 0.5 * lambert;
            col += dawn.glow * grazing * (0.05 + 0.42 * facing * (0.35 + 0.65 * relief));
            col += dawn.glow * rim * dawn.along * light * 0.35;
            float px = (position.x - dawn.cx) / (u.size.x * 0.22);
            float py = (depth - 0.11) / 0.07;
            col += dawn.deep * exp(-(px * px + py * py)) * light * 0.10;
            col *= 1.0 - 0.72 * smoothstep(0.03, 0.70, depth);

            float haze = exp(-depth * mix(40.0, 11.0, light)) * (0.30 + 0.55 * light) * u.haze;
            float3 hazeCol = mix(kField, dawn.glow * (0.30 + 0.45 * light), dawn.along);
            col = mix(col, hazeCol, clamp(haze * (0.35 + 0.65 * dawn.along), 0.0, 0.85));
            col *= 1.0 - 0.22 * exp(-depth * 55.0);
            return col;
        }

        static float3 horizonColor(float2 position, constant HorizonUniforms& u) {
            float2 size = u.size;
            float2 uv = position / size;

            float R = size.x * u.curvature;
            float2 c = float2(size.x * 0.5, u.arcY * size.y + R);
            float2 d = position - c;
            float sdf = length(d) - R;

            Dawn dawn;
            dawn.cx = size.x * (0.5 + 0.03 * u.travel);
            float lx = (position.x - dawn.cx) / (size.x * 0.5);
            float spread = mix(0.22, 0.50, u.light) + 0.62 * u.warmth;
            dawn.along = exp(-(lx * lx) / (spread * spread));
            dawn.along *= 1.0 - u.shimmer * 0.10 * (vnoise(float2(lx * 2.5 + u.time * 0.045, u.time * 0.02)) - 0.5);
            dawn.glow = mix(kInk, kRest, u.warmth);
            dawn.deep = mix(kInk * 0.6, kRestDeep, u.warmth);

            float aa = 1.5 * u.pixel;
            float t = smoothstep(-aa, aa, sdf);
            float3 col;
            if (t >= 1.0) {
                col = skyColor(sdf, position, u, dawn);
            } else if (t <= 0.0) {
                col = surfaceColor(sdf, d, R, position, u, dawn);
            } else {
                col = mix(surfaceColor(sdf, d, R, position, u, dawn), skyColor(sdf, position, u, dawn), t);
            }

            float g = hash21(floor(position / (1.5 * u.pixel)) + floor(u.time * 24.0) * 3.1) - 0.5;
            float lum = dot(col, float3(0.3, 0.59, 0.11));
            col += g * u.grain * (0.25 + 2.0 * lum * (1.0 - lum));

            col = mix(col, kField, smoothstep(0.42, 0.0, uv.y) * 0.5);
            return clamp(col, 0.0, 1.0);
        }

        struct HorizonVertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex HorizonVertexOut horizonVertex(uint vid [[vertex_id]]) {
            float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
            HorizonVertexOut out;
            out.position = float4(p, 0.0, 1.0);
            out.uv = float2((p.x + 1.0) * 0.5, 1.0 - (p.y + 1.0) * 0.5);
            return out;
        }

        fragment half4 horizonFragment(HorizonVertexOut in [[stage_in]], constant HorizonUniforms& u [[buffer(0)]]) {
            float3 col = horizonColor(in.uv * u.size, u);
            return half4(half3(col), 1.0h);
        }
        """#
}

/// Must match `HorizonUniforms` in the shader source, field for field.
struct HorizonUniforms: Equatable {
    var size: SIMD2<Float>
    var time: Float
    var light: Float
    var warmth: Float
    var turn: Float
    var travel: Float
    var arcY: Float
    var grain: Float
    var shimmer: Float
    var relief: Float
    var curvature: Float
    var pixel: Float
    var haze: Float
    var stars: Float
    var meteorT: Float
    var meteorSeed: Float

    init(state: HorizonState, time: Double, ambient: Bool, meteorElapsed: Double?, meteorSeed: Double) {
        let live = ambient && !state.frozen
        size = SIMD2(1, 1)
        self.time = Float(live ? time : 0)
        light = Float(state.light)
        warmth = Float(state.warmth)
        turn = Float(state.turn)
        travel = Float(state.travel)
        arcY = Float(HorizonTuning.arcY)
        grain = Float(HorizonTuning.grain)
        shimmer = live ? 1 : 0
        relief = Float(HorizonTuning.relief)
        curvature = Float(HorizonTuning.curvature)
        pixel = 0.5
        haze = Float(HorizonTuning.haze)
        stars = Float(HorizonTuning.stars)
        meteorT = Float(live ? (meteorElapsed ?? -1) : -1)
        self.meteorSeed = Float(meteorSeed)
    }
}

/// Compiles the horizon shader once per process and owns its pipeline.
@MainActor
final class HorizonRenderer {
    static let shared: HorizonRenderer? = HorizonRenderer()

    /// False where Metal is unavailable or the shader failed to compile; the
    /// backdrop then falls back to the bundled artwork.
    static var isAvailable: Bool { shared != nil }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            return nil
        }
        do {
            let library = try device.makeLibrary(source: HorizonShaderSource.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "horizonVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "horizonFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }
        self.device = device
        self.queue = queue
    }

    func draw(into layer: CAMetalLayer, uniforms: HorizonUniforms) {
        guard let drawable = layer.nextDrawable(), let commandBuffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 9 / 255, green: 10 / 255, blue: 12 / 255, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        var u = uniforms
        encoder.setFragmentBytes(&u, length: MemoryLayout<HorizonUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

@MainActor
private func configure(_ layer: CAMetalLayer) {
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.isOpaque = true
    layer.backgroundColor = CGColor(srgbRed: 9 / 255, green: 10 / 255, blue: 12 / 255, alpha: 1)
    if let device = HorizonRenderer.shared?.device {
        layer.device = device
    }
}

#if os(macOS)
    final class HorizonMetalView: NSView {
        let metalLayer = CAMetalLayer()
        var uniforms: HorizonUniforms?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            configure(metalLayer)
            layer = metalLayer
        }

        required init?(coder: NSCoder) { fatalError("HorizonMetalView is code-only") }

        override var wantsUpdateLayer: Bool { true }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            render()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            render()
        }

        func render() {
            guard var uniforms, bounds.width > 0, bounds.height > 0, let renderer = HorizonRenderer.shared else {
                return
            }
            let scale = window?.backingScaleFactor ?? 2
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            uniforms.size = SIMD2(Float(bounds.width), Float(bounds.height))
            uniforms.pixel = Float(1 / scale)
            self.uniforms = uniforms
            renderer.draw(into: metalLayer, uniforms: uniforms)
        }
    }

    struct HorizonMetalRepresentable: NSViewRepresentable {
        var uniforms: HorizonUniforms

        func makeNSView(context: Context) -> HorizonMetalView {
            let view = HorizonMetalView(frame: .zero)
            view.uniforms = uniforms
            return view
        }

        func updateNSView(_ view: HorizonMetalView, context: Context) {
            view.uniforms = uniforms
            view.render()
        }
    }
#elseif os(iOS)
    final class HorizonMetalView: UIView {
        override class var layerClass: AnyClass { CAMetalLayer.self }
        var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
        var uniforms: HorizonUniforms?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = true
            configure(metalLayer)
        }

        required init?(coder: NSCoder) { fatalError("HorizonMetalView is code-only") }

        override func layoutSubviews() {
            super.layoutSubviews()
            render()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            render()
        }

        func render() {
            guard var uniforms, bounds.width > 0, bounds.height > 0, let renderer = HorizonRenderer.shared else {
                return
            }
            let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            uniforms.size = SIMD2(Float(bounds.width), Float(bounds.height))
            uniforms.pixel = Float(1 / scale)
            self.uniforms = uniforms
            renderer.draw(into: metalLayer, uniforms: uniforms)
        }
    }

    struct HorizonMetalRepresentable: UIViewRepresentable {
        var uniforms: HorizonUniforms

        func makeUIView(context: Context) -> HorizonMetalView {
            let view = HorizonMetalView(frame: .zero)
            view.uniforms = uniforms
            return view
        }

        func updateUIView(_ view: HorizonMetalView, context: Context) {
            view.uniforms = uniforms
            view.render()
        }
    }
#endif

/// The rendered Distant Horizon. It draws only when SwiftUI updates it, so the
/// caller decides the ambient cadence; a frozen state draws once and rests.
/// `Animatable` lets a phase change ease the dawn instead of snapping it.
public struct HorizonSceneView: View, @preconcurrency Animatable {
    public var state: HorizonState
    /// Seconds driving grain, shimmer, and star drift. Ignored unless `ambient`.
    public var time: Double
    public var ambient: Bool
    /// Seconds since a meteor began, or nil. Rare, random, never scheduled.
    public var meteorElapsed: Double?
    public var meteorSeed: Double

    public init(
        state: HorizonState, time: Double = 0, ambient: Bool = false,
        meteorElapsed: Double? = nil, meteorSeed: Double = 0
    ) {
        self.state = state
        self.time = time
        self.ambient = ambient
        self.meteorElapsed = meteorElapsed
        self.meteorSeed = meteorSeed
    }

    public var animatableData: HorizonState.AnimatableData {
        get { state.animatableData }
        set { state.animatableData = newValue }
    }

    public var body: some View {
        HorizonMetalRepresentable(
            uniforms: HorizonUniforms(
                state: state, time: time, ambient: ambient, meteorElapsed: meteorElapsed, meteorSeed: meteorSeed)
        )
        .accessibilityHidden(true)
    }
}
