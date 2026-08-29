import AppKit
import FlowmoCore
import FlowmoLook
import SwiftUI

/// The selected Focus Scene: one large, movable, open-ended Focus canvas. It is
/// presentation only; the clock still comes from Core's persisted timestamps.
struct DistantHorizonScene: View {
    @ObservedObject var controller: FlowmoSessionController
    let status: SessionStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var titleScale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var interfaceScale: CGFloat = 1
    @State private var dragStartOrigin: NSPoint?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let horizontalInset = min(240, max(48, size.width * 0.0806))
            let headerTop = min(208, max(size.height < 700 ? size.height * 0.09 : 72, size.height * 0.121))
            let bottomInset = min(128, max(40, size.height * 0.0703))
            let compact = size.width < 900
            let controlSize = min(34, max(17, size.width * 0.011) * interfaceScale)

            ZStack {
                DistantHorizonBackdrop()
                    .contentShape(Rectangle())
                    .gesture(sceneDragGesture)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    sceneHeader(compact: compact, width: size.width)
                        .frame(
                            maxWidth: min(
                                920,
                                min(
                                    max(760, size.width * 0.36),
                                    size.width - (horizontalInset * 2)
                                )
                            ),
                            alignment: .leading
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, headerTop)

                    Spacer(minLength: 120)

                    sceneActions(controlSize: controlSize)
                        .frame(height: 44)
                        .padding(.bottom, bottomInset)
                }
                .padding(.horizontal, horizontalInset)
            }
            .frame(width: size.width, height: size.height)
        }
        .background(Atmosphere.canvas.field)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sceneDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let window = controller.attention.window else { return }
                if dragStartOrigin == nil {
                    dragStartOrigin = window.frame.origin
                }
                guard let dragStartOrigin else { return }
                window.setFrameOrigin(
                    FocusSceneWindowDrag.origin(
                        from: dragStartOrigin,
                        translation: value.translation
                    )
                )
            }
            .onEnded { _ in
                dragStartOrigin = nil
            }
    }

    @ViewBuilder
    private func sceneHeader(compact: Bool, width: CGFloat) -> some View {
        let kickerSize = min(30, max(13, width * 0.009) * interfaceScale)
        let baseIntentionSize = compact ? 34 : min(104, max(68, width * 0.038))
        let intentionSize = min(compact ? 56 : 112, baseIntentionSize * titleScale)
        let baseClockSize = compact ? 26 : min(64, max(34, width * 0.022))
        let clockSize = min(76, baseClockSize * interfaceScale)
        let spacing = min(22, max(11, width * 0.0076))

        if let interception = controller.focusGuard.runtime.interception {
            VStack(alignment: .leading, spacing: spacing) {
                Text("Focus Guard")
                    .font(.system(size: kickerSize, weight: .medium, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(Atmosphere.canvas.mute)
                Text("\(interception.displayName) is guarded.")
                    .font(.system(size: intentionSize, weight: .regular, design: .rounded))
                    .foregroundStyle(Atmosphere.canvas.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                InstrumentClock(Format.clock(status.elapsed), size: clockSize)
                    .foregroundStyle(Atmosphere.rest)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Focus Guard. \(interception.displayName) is guarded. Focused \(Format.clock(status.elapsed))."
            )
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                Text("Focus scene")
                    .font(.system(size: kickerSize, weight: .medium, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(Atmosphere.canvas.mute)
                Text(status.intention)
                    .font(.system(size: intentionSize, weight: .regular, design: .rounded))
                    .foregroundStyle(Atmosphere.canvas.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                InstrumentClock(Format.clock(status.elapsed), size: clockSize)
                    .foregroundStyle(Atmosphere.rest)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Focus Scene. \(status.intention). Focused \(Format.clock(status.elapsed))."
            )
        }
    }

    @ViewBuilder
    private func sceneActions(controlSize: CGFloat) -> some View {
        if controller.focusGuard.runtime.interception != nil {
            HStack {
                DistantHorizonAction("Stay focused", tone: Atmosphere.rest, fontSize: controlSize) {
                    controller.stayFocused()
                }
                .help("Keep this app hidden and return to prior work when available")

                Spacer()

                DistantHorizonAction("Open once", tone: Atmosphere.canvas.ink, fontSize: controlSize) {
                    controller.openOnce()
                }
                .help("Allow this guarded app once")
            }
        } else {
            HStack {
                DistantHorizonAction("End focus", tone: Atmosphere.rest, fontSize: controlSize) {
                    controller.stopFocus()
                }
                .help("Stop Focus and start your earned break")
                .accessibilityHint("Stops Focus and starts your earned break.")

                Spacer()

                DistantHorizonAction("Back to window", tone: Atmosphere.canvas.ink, fontSize: controlSize) {
                    controller.leaveFocusScene()
                }
                .help("Return to the normal Flowmo window; Focus keeps running")
                .accessibilityHint(
                    "Returns to the normal Flowmo window. Focus keeps running."
                )
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}

private struct DistantHorizonBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
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

private struct DistantHorizonAction: View {
    let title: String
    let tone: Color
    let fontSize: CGFloat
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool
    @State private var hovering = false

    init(_ title: String, tone: Color, fontSize: CGFloat, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.fontSize = fontSize
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(hovering || focused ? Atmosphere.canvas.ink : tone)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .background {
                    Capsule()
                        .fill(Atmosphere.canvas.ink.opacity(hovering ? 0.16 : 0))
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    Atmosphere.canvas.ink.opacity(focused ? 0.52 : (hovering ? 0.28 : 0)),
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color: Atmosphere.canvas.ink.opacity(focused ? 0.22 : 0),
                            radius: focused ? 3 : 0
                        )
                }
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressStyle())
        .focused($focused)
        .onHover { hovering = isEnabled && $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.hover, value: focused)
    }
}
