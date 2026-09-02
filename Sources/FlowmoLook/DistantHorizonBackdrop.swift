import SwiftUI

/// The shared Distant Horizon atmosphere. It is ambient geometry only: never
/// progress, a deadline, or session state.
public struct DistantHorizonBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let centerY = size.height * 0.636

            ZStack {
                Atmosphere.canvas.field

                DistantHorizonFloor()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(0.01), location: 0.55),
                                .init(color: Color.black.opacity(0.12), location: 0.70),
                                .init(color: Color.black.opacity(0.30), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: Atmosphere.canvas.ink.opacity(0.22), location: 0),
                                    .init(color: Atmosphere.canvas.ink.opacity(0.16), location: 0.18),
                                    .init(color: Atmosphere.rest.opacity(0.16), location: 0.40),
                                    .init(color: Atmosphere.restDeep.opacity(0.07), location: 0.68),
                                    .init(color: .clear, location: 1),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: min(500, size.width * 0.25)
                            )
                        )
                        .frame(
                            width: min(1_000, size.width * 0.55),
                            height: max(90, size.height * 0.095)
                        )
                        .blur(radius: 24)
                        .position(x: size.width / 2, y: centerY - (size.height * 0.018))

                    DistantHorizonArc()
                        .stroke(Atmosphere.restDeep.opacity(0.075), lineWidth: 30)
                        .blur(radius: 48)

                    DistantHorizonArc()
                        .stroke(Atmosphere.rest.opacity(0.16), lineWidth: 4)
                        .blur(radius: 11)

                    DistantHorizonArc()
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Atmosphere.restDeep.opacity(0.36), location: 0),
                                    .init(color: Atmosphere.restDeep.opacity(0.66), location: 0.25),
                                    .init(color: Atmosphere.rest, location: 0.36),
                                    .init(color: Atmosphere.canvas.ink.opacity(0.98), location: 0.42),
                                    .init(color: Atmosphere.canvas.ink, location: 0.50),
                                    .init(color: Atmosphere.canvas.ink.opacity(0.98), location: 0.58),
                                    .init(color: Atmosphere.rest, location: 0.64),
                                    .init(color: Atmosphere.restDeep.opacity(0.66), location: 0.75),
                                    .init(color: Atmosphere.restDeep.opacity(0.36), location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
                        )
                        .shadow(color: Atmosphere.rest.opacity(0.38), radius: 7)
                }
                .frame(width: size.width, height: size.height)
                .opacity(breathing && !reduceMotion ? 1 : 0.97)
                .scaleEffect(x: 1, y: breathing && !reduceMotion ? 1.002 : 0.999, anchor: .center)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 12).repeatForever(autoreverses: true),
                    value: breathing
                )
                .onAppear {
                    breathing = !reduceMotion
                }
                .onChange(of: reduceMotion) { _, reduced in
                    breathing = !reduced
                }
            }
            .drawingGroup(opaque: true, colorMode: .linear)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct DistantHorizonArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.6836))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.6836),
            control: CGPoint(x: rect.midX, y: rect.height * 0.5889)
        )
        return path
    }
}

private struct DistantHorizonFloor: Shape {
    func path(in rect: CGRect) -> Path {
        var path = DistantHorizonArc().path(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
