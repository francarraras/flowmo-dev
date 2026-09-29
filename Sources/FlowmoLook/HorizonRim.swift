import SwiftUI

/// The compact instrument's share of the Distant Horizon: the aperture seen
/// from above, with the dawn on its lower rim. It reads the same `HorizonState`
/// as the Scene, so Prime opens the arc, Focus warms it as rest is earned, and
/// Break closes it. Everything stays concentric on the aperture; the circle
/// itself never moves or changes size.
struct HorizonRim: View, @preconcurrency Animatable {
    var state: HorizonState
    var diameter: CGFloat

    var animatableData: HorizonState.AnimatableData {
        get { state.animatableData }
        set { state.animatableData = newValue }
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            Self.draw(&context, size: size, state: state, diameter: diameter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, state: HorizonState, diameter: CGFloat) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = diameter / 2
        let light = max(0, min(1, state.light))
        guard light > 0.001 else { return }
        let lightColor = mix(Atmosphere.canvas.ink, Atmosphere.rest, state.warmth)
        let deepColor = mix(Atmosphere.canvas.ink, Atmosphere.restDeep, state.warmth)

        // Dawn pool: the light reaches past the rim into the field below.
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [
                    lightColor.opacity(0.20 * light), lightColor.opacity(0.06 * light), lightColor.opacity(0),
                ]),
                center: CGPoint(x: c.x, y: c.y + r * 0.92), startRadius: 0, endRadius: r * 1.35)
        )

        // The lit arc. Its reach grows with the light: Prime opens it, Break closes it.
        let halfSpan = 22 + 66 * light
        let arc = lowerArc(center: c, radius: r, halfSpanDegrees: halfSpan)
        func gradient(_ alpha: Double, _ color: Color) -> GraphicsContext.Shading {
            .linearGradient(
                Gradient(stops: [
                    .init(color: color.opacity(0), location: 0),
                    .init(color: color.opacity(alpha * 0.7), location: 0.32),
                    .init(color: color.opacity(alpha), location: 0.5),
                    .init(color: color.opacity(alpha * 0.7), location: 0.68),
                    .init(color: color.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: c.x - r * 1.05, y: 0), endPoint: CGPoint(x: c.x + r * 1.05, y: 0))
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: max(10, r * 0.22)))
            layer.stroke(
                arc, with: gradient(0.55 * light, deepColor),
                style: StrokeStyle(lineWidth: max(6, r * 0.10), lineCap: .round))
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: max(4, r * 0.06)))
            layer.stroke(
                arc, with: gradient(0.30 + 0.60 * light, lightColor),
                style: StrokeStyle(lineWidth: 3 + 2 * light, lineCap: .round))
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.6))
            layer.stroke(
                arc, with: gradient(min(1, 0.45 + 0.75 * light), lightColor),
                style: StrokeStyle(lineWidth: 1.5 + 1.5 * light, lineCap: .round))
        }
    }

    /// Dawn glow inside the well, just above the lit rim.
    static func drawInnerGlow(_ ctx: inout GraphicsContext, size: CGSize, state: HorizonState) {
        let light = max(0, min(1, state.light))
        guard light > 0.001 else { return }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = min(size.width, size.height) / 2
        let lightColor = mix(Atmosphere.canvas.ink, Atmosphere.rest, state.warmth)
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
            with: .radialGradient(
                Gradient(colors: [
                    lightColor.opacity(0.22 * light), lightColor.opacity(0.05 * light), lightColor.opacity(0),
                ]),
                center: CGPoint(x: c.x, y: c.y + r), startRadius: 0, endRadius: r * (0.55 + 0.35 * light))
        )
    }

    /// Screen angles: 90° is straight down.
    private static func lowerArc(center: CGPoint, radius: CGFloat, halfSpanDegrees: Double) -> Path {
        var path = Path()
        let samples = 64
        for i in 0...samples {
            let degrees = 90 - halfSpanDegrees + (2 * halfSpanDegrees) * Double(i) / Double(samples)
            let t = degrees * .pi / 180
            let p = CGPoint(x: center.x + radius * CGFloat(cos(t)), y: center.y + radius * CGFloat(sin(t)))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let k = max(0, min(1, t))
        let ca = a.resolve(in: EnvironmentValues())
        let cb = b.resolve(in: EnvironmentValues())
        return Color(
            .sRGB,
            red: Double(ca.red) + (Double(cb.red) - Double(ca.red)) * k,
            green: Double(ca.green) + (Double(cb.green) - Double(ca.green)) * k,
            blue: Double(ca.blue) + (Double(cb.blue) - Double(ca.blue)) * k,
            opacity: 1)
    }
}

/// Inner glow as a view so `Aperture` can clip it to the well.
struct HorizonInnerGlow: View, @preconcurrency Animatable {
    var state: HorizonState

    var animatableData: HorizonState.AnimatableData {
        get { state.animatableData }
        set { state.animatableData = newValue }
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            HorizonRim.drawInnerGlow(&context, size: size, state: state)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
