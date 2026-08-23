import SwiftUI
import FlowmoCore
import FlowmoLook

public struct PhoneRootView: View {
    @ObservedObject var controller: PhoneSessionController

    public init(controller: PhoneSessionController) {
        self.controller = controller
    }

    public var body: some View {
        let status = controller.status
        let atmo = Atmosphere.of(status)
        Group {
            if status.isIdle {
                IdlePane(controller: controller, status: status)
            } else {
                phasePane(status)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 12)
        .foregroundStyle(atmo.ink)
        .background(FieldCanvas())
        .environment(\.atmosphere, atmo)
        .animation(Motion.phase, value: status.isPaused)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                muteButton(atmo)
            }
            .opacity(atmo.chrome)
        }
    }

    private func muteButton(_ atmo: Atmosphere) -> some View {
        let on = controller.world.config.cuesEnabled
        return Button {
            controller.setCuesEnabled(!on)
        } label: {
            ChromeGlyph(on ? "speaker.wave.2" : "speaker.slash", lit: on)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(on ? "Mute cues" : "Unmute cues")
    }

    @ViewBuilder
    private func phasePane(_ status: SessionStatus) -> some View {
        switch status.phase {
        case .prime:
            PrimePane(controller: controller, status: status)
        case .focus:
            FocusPane(controller: controller, status: status)
        case .onBreak:
            BreakPane(controller: controller, status: status)
        case .recall:
            RecallPane(controller: controller, status: status)
        case .closeBeat:
            CloseBeatPane(controller: controller, status: status)
        case nil:
            IdlePane(controller: controller, status: status)
        }
    }
}

private struct IdlePane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus
    @State private var showingHistory = false

    var body: some View {
        Group {
            if showingHistory {
                HistoryPane(sessions: HistoryOrder.newestFirst(controller.world.history)) {
                    showingHistory = false
                }
            } else {
                PhaseColumn {
                    HairlineField("Intention", text: $controller.intentionDraft)
                } hole: {
                    Aperture(ring: .idle)
                } verb: {
                    InkButton("Start") {
                        controller.start()
                    }
                    .disabled(controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } chrome: {
                    HStack(spacing: 18) {
                        Text("Today \(Format.clock(status.todayFocusSeconds))")
                            .foregroundStyle(atmo.faint)
                            .monospacedDigit()
                        Button {
                            showingHistory = true
                        } label: {
                            Text("History")
                                .underline(false)
                                .modifier(QuietHoverInk())
                        }
                        .buttonStyle(PressStyle())
                        if !controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                controller.clearIntention()
                            } label: {
                                Text("New")
                                    .underline(false)
                                    .modifier(QuietHoverInk())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .padding(.top, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryPane: View {
    @Environment(\.atmosphere) private var atmo
    var sessions: [CompletedSession]
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                QuietButton("Back", minHeight: 44, action: dismiss)
                Spacer()
                Text("History")
                    .font(.system(.headline, design: .rounded))
            }
            if sessions.isEmpty {
                Text("No completed sessions yet.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(atmo.mute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sessions, id: \.id) { session in
                            HistorySessionCard(session: session)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PrimePane: View {
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseLead(status.intention, cue: "Prepare")
        } hole: {
            Aperture(ring: .timed(progress: ringProgress(status))) {
                InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 40)
            }
        } verb: {
            if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
            } else {
                QuietButton("Skip", minHeight: 44) { controller.skip() }
            }
        }
    }
}

private struct FocusPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus
    @FocusState private var captureFocused: Bool

    var body: some View {
        PhaseColumn {
            if controller.showCapture, !status.isPaused {
                HairlineField("Park a thought", text: $controller.captureDraft)
                    .focused($captureFocused)
                    .onSubmit { controller.submitCapture() }
                    .onAppear { captureFocused = true }
            } else {
                PhaseLead(status.intention, cue: "Focus", tone: atmo.mute)
            }
        } hole: {
            Aperture(ring: .none) {
                VStack(spacing: 10) {
                    InstrumentClock(Format.clock(status.elapsed), size: 56)
                        .milestoneGrow(elapsed: status.elapsed, paused: status.isPaused)
                    Accrual(seconds: status.earnedBreakSeconds, label: Format.earned(status.earnedBreakSeconds))
                }
            }
        } verb: {
            if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
            } else if controller.showCapture {
                HStack(spacing: 10) {
                    QuietButton("Discard", minHeight: 44) { controller.discardCapture() }
                    InkButton("Park") { controller.submitCapture() }
                        .disabled(controller.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack {
                    Button {
                        controller.showCapture = true
                    } label: {
                        ChromeGlyph("plus")
                            .frame(width: 44, height: PhaseGrid.verb)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Park a thought")
                    QuietButton("Stop", minHeight: 44) { controller.stopFocus() }
                }
            }
        }
    }
}

private struct BreakPane: View {
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseCaption("Time to recharge", tone: Look.mute)
        } hole: {
            Aperture(ring: .timed(
                progress: ringProgress(status),
                rest: true,
                race: !status.isPaused && (status.remaining ?? 0) <= 10
            )) {
                InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 40)
                    .breakRace(
                        remaining: status.remaining ?? 0,
                        elapsed: status.elapsed,
                        paused: status.isPaused
                    )
            }
        } verb: {
            if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
            } else {
                QuietButton("Skip", minHeight: 44) { controller.skip() }
            }
        }
    }
}

private struct RecallPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            if status.isPaused {
                PhaseCaption(status.recallText.isEmpty ? "Reflection" : status.recallText, tone: atmo.mute)
            } else {
                HairlineField("What did you just do?", text: $controller.recallDraft, centered: true)
                    .onChange(of: controller.recallDraft) { _ in
                        controller.persistRecall()
                    }
                    .onSubmit { controller.skip() }
            }
        } hole: {
            Aperture(ring: .timed(progress: ringProgress(status))) {
                InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 40)
            }
        } verb: {
            if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
            } else {
                QuietButton("Skip", minHeight: 44) { controller.skip() }
            }
        }
    }
}

private struct CloseBeatPane: View {
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseCaption(status.intention.isEmpty ? "Close" : status.intention, tone: Look.mute)
        } hole: {
            Aperture(ring: .none) {
                CloseFigures(focus: status.focusSeconds, rest: status.breakSeconds ?? 0)
            }
        } verb: {
            if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !status.isPaused {
                controller.dismissCloseBeat()
            }
        }
    }
}

private func ringProgress(_ status: SessionStatus) -> Double {
    guard let duration = status.phaseDuration, duration > 0 else { return 0 }
    return min(1, max(0, status.elapsed / duration))
}
