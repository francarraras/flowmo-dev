import AppKit
import UniformTypeIdentifiers
import SwiftUI
import FlowmoCore
import FlowmoLook

struct FlowmoRootView: View {
    @ObservedObject var controller: FlowmoSessionController

    var body: some View {
        let status = controller.status
        let atmo = Atmosphere.of(status)
        let mini = controller.displayMode == .mini
        let size = controller.displayMode.windowContentSize
        Group {
            if mini {
                MiniView(controller: controller, status: status)
            } else if status.isIdle {
                IdlePane(controller: controller, status: status)
            } else {
                phasePane(status)
            }
        }
        .padding(.horizontal, mini ? 6 : 16)
        .padding(.bottom, mini ? 8 : 14)
        .padding(.top, mini ? 26 : 28)
        .frame(width: size.width, height: size.height)
        .foregroundStyle(atmo.ink)
        .background(FieldCanvas())
        .environment(\.atmosphere, atmo)
        .animation(Motion.phase, value: status.isPaused)
        .animation(Motion.phase, value: controller.displayMode)
        .preferredColorScheme(.dark)
        .overlay(alignment: .topLeading) {
            if mini {
                HStack(spacing: 0) {
                    muteButton(atmo, compact: true)
                    pinButton(atmo, compact: true)
                }
                .padding(.leading, 52)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if mini {
                    modeButton(atmo, to: .classic, icon: "arrow.up.left.and.arrow.down.right", help: "Expand to Classic", compact: true)
                        .padding(.trailing, 4)
                } else {
                    muteButton(atmo)
                    pinButton(atmo)
                    modeButton(atmo, to: .mini, icon: "arrow.down.right.and.arrow.up.left", help: "Shrink to Mini")
                        .padding(.trailing, 8)
                }
            }
            .opacity(mini ? 1 : atmo.chrome)
        }
        .background(WindowPin(pinned: controller.isPinned, field: atmo.field))
    }

    private func modeButton(
        _ atmo: Atmosphere,
        to mode: DisplayMode,
        icon: String,
        help: String,
        compact: Bool = false
    ) -> some View {
        Button {
            controller.setDisplayMode(mode)
        } label: {
            ChromeGlyph(icon, compact: compact)
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel(help)
        .padding(.top, compact ? 6 : 4)
    }

    private func muteButton(_ atmo: Atmosphere, compact: Bool = false) -> some View {
        let on = controller.world.config.cuesEnabled
        return Button {
            controller.setCuesEnabled(!on)
        } label: {
            ChromeGlyph(on ? "speaker.wave.2" : "speaker.slash", lit: on, compact: compact)
        }
        .buttonStyle(PressStyle())
        .help(on ? "Mute cues" : "Unmute cues")
        .accessibilityLabel(on ? "Mute cues" : "Unmute cues")
        .padding(.top, compact ? 6 : 4)
    }

    private func pinButton(_ atmo: Atmosphere, compact: Bool = false) -> some View {
        Button {
            controller.isPinned.toggle()
        } label: {
            ChromeGlyph(controller.isPinned ? "pin.fill" : "pin", lit: controller.isPinned, compact: compact)
        }
        .buttonStyle(PressStyle())
        .help(controller.isPinned ? "Unpin" : "Pin on top")
        .accessibilityLabel(controller.isPinned ? "Unpin" : "Pin on top")
        .padding(.top, compact ? 6 : 4)
        .padding(.trailing, compact ? 0 : 8)
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
    @ObservedObject var controller: FlowmoSessionController
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
                    FlowField(
                        "Intention",
                        text: $controller.intentionDraft,
                        autofocus: true,
                        focusDelay: 0.45,
                        onSubmit: {
                            let trimmed = controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            controller.start()
                        }
                    )
                } hole: {
                    Aperture(ring: .idle)
                } verb: {
                    InkButton("Start") {
                        controller.start()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } chrome: {
                    VStack(spacing: 12) {
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
                        GuardConfig(controller: controller)
                    }
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
        VStack(spacing: 10) {
            HStack {
                QuietButton("Back", action: dismiss)
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
                    LazyVStack(spacing: 8) {
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
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseLead(status.intention, cue: "Prepare")
        } hole: {
            Aperture(ring: .timed(progress: ringProgress(status))) {
                InstrumentClock(Format.remainingClock(status.remaining ?? 0))
            }
        } verb: {
            if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
                    .keyboardShortcut(.defaultAction)
            } else {
                QuietButton("Skip") { controller.skip() }
            }
        }
    }
}

private struct FocusPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            if let hit = controller.focusGuard.runtime.interception, !status.isPaused {
                PhaseCaption("\(hit.displayName) is guarded.", tone: atmo.mute)
            } else if controller.showCapture, !status.isPaused {
                FlowField(
                    "Park a thought",
                    text: $controller.captureDraft,
                    autofocus: true,
                    focusDelay: 0.12,
                    onSubmit: { controller.submitCapture() },
                    onCancel: { controller.discardCapture() }
                )
            } else {
                PhaseLead(status.intention, cue: "Focus", tone: atmo.mute)
            }
        } hole: {
            Aperture(ring: .none) {
                VStack(spacing: 10) {
                    InstrumentClock(Format.clock(status.elapsed), size: 52)
                        .milestoneGrow(elapsed: status.elapsed, paused: status.isPaused)
                    Accrual(seconds: status.earnedBreakSeconds, label: Format.earned(status.earnedBreakSeconds))
                }
            }
        } verb: {
            if controller.focusGuard.runtime.interception != nil, !status.isPaused {
                HStack(spacing: 12) {
                    QuietButton("Stay") { controller.stayFocused() }
                    InkButton("Open once") { controller.openOnce() }
                }
            } else if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
                    .keyboardShortcut(.defaultAction)
            } else if controller.showCapture {
                HStack(spacing: 10) {
                    QuietButton("Discard") { controller.discardCapture() }
                    InkButton("Park") { controller.submitCapture() }
                        .disabled(controller.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack {
                    Button {
                        controller.showCapture = true
                    } label: {
                        ChromeGlyph("plus")
                    }
                    .buttonStyle(PressStyle())
                    .help("Park a thought")
                    .accessibilityLabel("Park a thought")
                    QuietButton("Stop") { controller.stopFocus() }
                }
            }
        }
    }
}

private struct BreakPane: View {
    @ObservedObject var controller: FlowmoSessionController
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
                InstrumentClock(Format.remainingClock(status.remaining ?? 0))
                    .breakRace(
                        remaining: status.remaining ?? 0,
                        elapsed: status.elapsed,
                        paused: status.isPaused
                    )
            }
        } verb: {
            if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
                    .keyboardShortcut(.defaultAction)
            } else {
                QuietButton("Skip") { controller.skip() }
            }
        }
    }
}

private struct RecallPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            if status.isPaused {
                PhaseCaption(status.recallText.isEmpty ? "Reflection" : status.recallText, tone: atmo.mute)
            } else {
                FlowField(
                    "What did you just do?",
                    text: $controller.recallDraft,
                    centered: true,
                    autofocus: true,
                    focusDelay: 0.55,
                    onSubmit: { controller.skip() }
                )
                .onChange(of: controller.recallDraft) { _ in
                    controller.persistRecall()
                }
            }
        } hole: {
            Aperture(ring: .timed(progress: ringProgress(status))) {
                InstrumentClock(Format.remainingClock(status.remaining ?? 0))
            }
        } verb: {
            if status.isPaused {
                InkButton("Continue") { controller.continueSession() }
                    .keyboardShortcut(.defaultAction)
            } else {
                QuietButton("Skip") { controller.skip() }
            }
        }
    }
}

private struct CloseBeatPane: View {
    @ObservedObject var controller: FlowmoSessionController
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
                    .keyboardShortcut(.defaultAction)
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

private struct GuardConfig: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController

    var body: some View {
        let config = controller.world.config.focusGuard
        VStack(spacing: 6) {
            Button {
                controller.showGuardConfig.toggle()
            } label: {
                Text(guardLabel(config))
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .underline(false)
                    .modifier(QuietHoverInk())
            }
            .buttonStyle(PressStyle())
            if controller.showGuardConfig {
                Toggle("On", isOn: Binding(
                    get: { config.enabled },
                    set: { controller.setGuardEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(atmo.mute)
                ForEach(config.bundleIdentifiers, id: \.self) { id in
                    HStack {
                        Text(displayName(id))
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            controller.removeGuardedApp(bundleIdentifier: id)
                        } label: {
                            Text("Remove")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .underline(false)
                                .modifier(QuietHoverInk())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                QuietButton("Add app") { pickApp() }
            }
        }
    }

    private func guardLabel(_ config: FocusGuardConfiguration) -> String {
        if !config.enabled || config.bundleIdentifiers.isEmpty {
            return "Guard: Off"
        }
        let n = config.bundleIdentifiers.count
        return n == 1 ? "Guard: 1 app" : "Guard: \(n) apps"
    }

    private func displayName(_ id: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return id
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { result in
            guard result == .OK else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier {
                    controller.addGuardedApp(bundleIdentifier: id)
                }
            }
        }
    }
}

private struct WindowPin: NSViewRepresentable {
    var pinned: Bool
    var field: Color

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.level = pinned ? .floating : .normal
        window.hidesOnDeactivate = false
        window.backgroundColor = NSColor(field)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isOpaque = true
        window.appearance = NSAppearance(named: .darkAqua)
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
