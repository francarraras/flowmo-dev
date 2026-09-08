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
                    .overlay(SceneDragSurface())
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
                    .font(.system(size: kickerSize, weight: .medium, design: .default))
                    .tracking(0.3)
                    .foregroundStyle(Atmosphere.canvas.mute)
                Text("\(interception.displayName) is guarded.")
                    .font(.system(size: intentionSize, weight: .regular, design: .default))
                    .foregroundStyle(Atmosphere.canvas.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                InstrumentClock(Format.clock(status.elapsed), size: clockSize)
                    .foregroundStyle(Atmosphere.canvas.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Focus Guard. \(interception.displayName) is guarded. Focused \(Format.clock(status.elapsed))."
            )
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                Text("Focus")
                    .font(.system(size: kickerSize, weight: .medium, design: .default))
                    .tracking(0.3)
                    .foregroundStyle(Atmosphere.canvas.mute)
                Text(status.intention)
                    .font(.system(size: intentionSize, weight: .regular, design: .default))
                    .foregroundStyle(Atmosphere.canvas.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                InstrumentClock(Format.clock(status.elapsed), size: clockSize)
                    .foregroundStyle(Atmosphere.canvas.ink)
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

private struct DistantHorizonAction: View {
    let title: String
    let tone: Color
    let fontSize: CGFloat
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .font(.system(size: fontSize, weight: .medium, design: .default))
                .foregroundStyle(hovering || focused ? Atmosphere.canvas.ink : tone)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Atmosphere.canvas.ink.opacity(hovering ? 0.10 : 0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    Atmosphere.canvas.ink.opacity(focused ? 0.6 : (hovering ? 0.30 : 0.16)),
                                    lineWidth: 1
                                )
                        }
                }
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressStyle())
        .focused($focused)
        .onHover { hovering = isEnabled && $0 }
        .animation(reduceMotion ? nil : Motion.hover, value: hovering)
        .animation(reduceMotion ? nil : Motion.hover, value: focused)
    }
}

/// Native tracking uses screen coordinates, so moving the window cannot feed
/// back into the gesture's translation. Controls above this surface keep clicks.
struct SceneDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> SceneDragView {
        SceneDragView(frame: .zero)
    }

    func updateNSView(_ nsView: SceneDragView, context: Context) {}
}

final class SceneDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
