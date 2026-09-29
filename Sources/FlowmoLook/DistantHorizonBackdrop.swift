import FlowmoCore
import SwiftUI

/// The Focus canvas background, shared by the Mac Scene and the phone's active
/// Focus. It renders the Distant Horizon from the current session: the dawn
/// rises through Prime, widens and warms with earned rest during Focus, and
/// sets through Break. Nothing here is a clock; `HorizonState` is a pure
/// projection of Core's timestamp-derived status, and Recovery Pause freezes it.
///
/// Ambient motion (grain, shimmer, star drift) runs at a low cadence only while
/// the scene is active and Reduce Motion is off. Where Metal is unavailable the
/// original bundled Horizon Study artwork is shown instead.
public struct DistantHorizonBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var state: HorizonState

    public init(status: SessionStatus) {
        self.state = HorizonState.of(status)
    }

    public init(state: HorizonState) {
        self.state = state
    }

    public var body: some View {
        Group {
            if HorizonRenderer.isAvailable {
                let live = ambientMotion && !state.frozen
                TimelineView(.animation(minimumInterval: 1 / HorizonTuning.ambientFramesPerSecond, paused: !live)) {
                    context in
                    HorizonSceneView(
                        state: state,
                        time: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600),
                        ambient: live
                    )
                    .animation(reduceMotion ? nil : Motion.light, value: state)
                }
            } else {
                HorizonStudyBackdrop(illuminated: ambientMotion)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var ambientMotion: Bool {
        !reduceMotion && scenePhase == .active
    }
}

/// The build 5–7 artwork backdrop, retained as the non-Metal fallback.
struct HorizonStudyBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var illuminated: Bool
    @State private var bright = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Atmosphere.canvas.field
                HorizonArtwork.image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .offset(y: size.height * 0.07)
                    .opacity(bright ? 1 : 0.94)
                    .animation(
                        illuminated ? .easeInOut(duration: 14).repeatForever(autoreverses: true) : nil,
                        value: bright
                    )
                LinearGradient(
                    stops: [
                        .init(color: Atmosphere.canvas.field.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.43),
                        .init(color: .clear, location: 0.73),
                        .init(color: Atmosphere.canvas.field.opacity(0.65), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .onAppear { bright = illuminated }
        .onChange(of: illuminated) { _, active in bright = active }
    }
}
