import FlowmoCore
import FlowmoLook
import SwiftUI

/// The smallest honest surface. One aperture owns the tile; verbs sit on the
/// lower arc. Anything that needs a keyboard routes back to Classic.
struct MiniView: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        VStack(spacing: 2) {
            Aperture(ring: ring, contentPadding: 10) { hole }
            verbRow
                .frame(height: 28)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if status.phase == .closeBeat, !status.isPaused {
                controller.dismissCloseBeat()
            } else if status.phase == nil || (status.phase == .recall && !status.isPaused) {
                controller.setDisplayMode(.classic)
            }
        }
    }

    @ViewBuilder
    private var hole: some View {
        switch status.phase {
        case .focus:
            VStack(spacing: 5) {
                InstrumentClock(Format.clock(status.elapsed), size: 34)
                    .milestoneGrow(elapsed: status.elapsed, paused: status.isPaused)
                Accrual(seconds: status.earnedBreakSeconds, label: Format.earned(status.earnedBreakSeconds))
            }
        case .closeBeat:
            CloseFigures(focus: status.focusSeconds, rest: status.breakSeconds ?? 0, compact: true)
        case .onBreak:
            InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 30)
                .breakRace(
                    remaining: status.remaining ?? 0,
                    elapsed: status.elapsed,
                    paused: status.isPaused
                )
        case nil:
            EmptyView()
        default:
            InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 30)
        }
    }

    private var ring: ApertureRing {
        switch status.phase {
        case .prime, .recall:
            return .timed(progress: ringProgress(status))
        case .onBreak:
            return .timed(
                progress: ringProgress(status),
                rest: true,
                race: !status.isPaused && (status.remaining ?? 0) <= 10
            )
        case nil:
            return .idle
        case .closeBeat, .focus:
            return .none
        }
    }

    @ViewBuilder
    private var verbRow: some View {
        if controller.focusGuard.runtime.interception != nil, !status.isPaused {
            HStack(spacing: 6) {
                QuietButton("Stay focused", minHeight: 26) { controller.stayFocused() }
                InkButton("Open once", compact: true) { controller.openOnce() }
            }
        } else if status.isPaused {
            RecoveryVerbs(
                compact: true,
                onRestart: { controller.restartSession() },
                onContinue: { controller.continueSession() }
            )
        } else {
            switch status.phase {
            case nil:
                InkButton("Start", compact: true) { controller.start() }
                    .disabled(controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .prime, .onBreak, .recall:
                QuietButton("Skip", minHeight: 26) { controller.skip() }
            case .focus:
                HStack(spacing: 8) {
                    miniIcon("plus", help: "Park a thought — opens Classic") {
                        controller.showCapture = true
                        controller.setDisplayMode(.classic)
                    }
                    QuietButton("Stop", minHeight: 26) { controller.stopFocus() }
                }
            case .closeBeat:
                EmptyView()
            }
        }
    }

    private func miniIcon(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(atmo.mute)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

private func ringProgress(_ status: SessionStatus) -> Double {
    guard let duration = status.phaseDuration, duration > 0 else { return 0 }
    return min(1, max(0, status.elapsed / duration))
}
