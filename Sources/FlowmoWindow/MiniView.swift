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
            if status.phase == nil || (status.phase == .recall && !status.isPaused) {
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
                Accrual(seconds: status.earnedBreakSeconds, label: Format.earned(status.earnedBreakSeconds))
            }
        case .closeBeat:
            MiniCloseSummary(status: status)
        case .onBreak:
            InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 30)
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
                QuietButton("Stay focused", minHeight: 26, compact: true) { controller.stayFocused() }
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
                InkButton(miniStartTitle, compact: true) { performIdleAction() }
                    .disabled(!canStart)
            case .prime:
                HStack(spacing: 6) {
                    miniIcon(
                        "rectangle.inset.filled",
                        help: "Start Focus in a large movable horizon scene"
                    ) {
                        controller.startFocusScene()
                    }
                    QuietButton("Focus now", minHeight: 26, compact: true) { controller.focusNow() }
                        .help(
                            "Starts Focus and returns to your previous work app when available and not guarded"
                        )
                        .accessibilityHint(
                            "Starts Focus and returns to your previous work app when available and not guarded."
                        )
                }
            case .recall:
                if canReviewParkedThoughts {
                    HStack(spacing: 8) {
                        miniIcon("tray.full", help: "Review parked thoughts — opens Classic") {
                            controller.beginParkedReview()
                            controller.setDisplayMode(.classic)
                        }
                        QuietButton(recallActionTitle, minHeight: 26, compact: true) { controller.skip() }
                    }
                } else {
                    QuietButton(recallActionTitle, minHeight: 26, compact: true) { controller.skip() }
                }
            case .onBreak:
                QuietButton("Reflect", minHeight: 26, compact: true) { controller.skip() }
            case .focus:
                HStack(spacing: 6) {
                    miniIcon("plus", help: "Park a thought — opens Classic") {
                        controller.showCapture = true
                        controller.setDisplayMode(.classic)
                    }
                    QuietButton(FocusSceneEntryControl.compactTitle, minHeight: 26, compact: true) {
                        controller.enterFocusScene()
                    }
                    .help(FocusSceneEntryControl.accessibilityLabel)
                    .accessibilityLabel(FocusSceneEntryControl.title)
                    .accessibilityHint(FocusSceneEntryControl.accessibilityHint)
                    QuietButton("Stop", minHeight: 26, compact: true) { controller.stopFocus() }
                }
            case .closeBeat:
                QuietButton("Done", minHeight: 26, compact: true) {
                    controller.dismissCloseBeat()
                    if controller.world.live == nil,
                        !controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        controller.setDisplayMode(.classic)
                    }
                }
                .help(closeActionHelp)
                .accessibilityHint(closeActionHelp)
            }
        }
    }

    private var canStart: Bool {
        !controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || NextStepSuggestion.latest(in: controller.world.history) != nil
            || !status.lastIntention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var miniStartTitle: String {
        let typed = controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = status.lastIntention.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty, NextStepSuggestion.latest(in: controller.world.history) != nil {
            return "Use next"
        }
        return typed.isEmpty && !saved.isEmpty ? "Use last" : "Start"
    }

    private func performIdleAction() {
        let typed = controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = status.lastIntention.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty, NextStepSuggestion.latest(in: controller.world.history) != nil {
            controller.useNextStep()
            controller.setDisplayMode(.classic)
        } else if typed.isEmpty && !saved.isEmpty {
            controller.useLastIntention()
            controller.setDisplayMode(.classic)
        } else {
            controller.start()
        }
    }

    private var recallActionTitle: String {
        controller.recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Skip"
            : "Done"
    }

    private var closeActionHelp: String {
        status.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Finish this session"
            : "Finish this session and open the next step in Classic for editing. Focus does not start."
    }

    private var canReviewParkedThoughts: Bool {
        !status.captures.isEmpty
            && controller.recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func miniIcon(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(.footnote, design: .default).weight(.medium))
                .foregroundStyle(atmo.mute)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct MiniCloseSummary: View {
    @Environment(\.atmosphere) private var atmo
    var status: SessionStatus

    var body: some View {
        VStack(spacing: 3) {
            InstrumentClock(Format.clock(status.focusSeconds), size: 24)
            Text("Focused")
                .foregroundStyle(atmo.mute)
            Text("Break earned · \(Format.clock(status.breakSeconds ?? 0))")
                .foregroundStyle(atmo.faint)
            if !nextStep.isEmpty {
                Text("Next: \(nextStep)")
                    .foregroundStyle(Atmosphere.rest)
                    .truncationMode(.tail)
            }
            if status.captures.count > 0 {
                Text(parkedLabel)
                    .foregroundStyle(atmo.faint)
            }
        }
        .font(.system(size: 8, weight: .medium, design: .default))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var nextStep: String {
        status.recallText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parkedLabel: String {
        status.captures.count == 1 ? "1 thought parked" : "\(status.captures.count) thoughts parked"
    }

    private var accessibilitySummary: String {
        var parts = [
            "Focused \(Format.clock(status.focusSeconds))",
            "Break earned \(Format.clock(status.breakSeconds ?? 0))",
        ]
        if !nextStep.isEmpty {
            parts.append("Next: \(nextStep)")
        }
        if status.captures.count > 0 {
            parts.append(parkedLabel)
        }
        return parts.joined(separator: ". ")
    }
}

private func ringProgress(_ status: SessionStatus) -> Double {
    guard let duration = status.phaseDuration, duration > 0 else { return 0 }
    return min(1, max(0, status.elapsed / duration))
}
