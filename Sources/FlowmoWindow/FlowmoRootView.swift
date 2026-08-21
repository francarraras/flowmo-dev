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
        VStack(spacing: 12) {
            Group {
                if status.isIdle {
                    IdlePane(controller: controller, status: status)
                } else {
                    phasePane(status)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if status.isPaused {
                VStack(spacing: 8) {
                    Kicker("Paused", tone: .mute)
                    InkButton("Continue") {
                        controller.continueSession()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(atmo.ink)
        .background(atmo.field)
        .environment(\.atmosphere, atmo)
        .animation(.easeInOut(duration: 0.9), value: status.phase)
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) {
                muteButton(atmo)
                pinButton(atmo)
            }
            .opacity(atmo.chrome)
            .animation(.easeInOut(duration: 0.9), value: atmo.chrome)
        }
        .background(WindowPin(pinned: controller.isPinned, field: atmo.field))
    }

    private func muteButton(_ atmo: Atmosphere) -> some View {
        let on = controller.world.config.cuesEnabled
        return Button {
            controller.setCuesEnabled(!on)
        } label: {
            Image(systemName: on ? "speaker.wave.2" : "speaker.slash")
                .font(.body.weight(.medium))
                .foregroundStyle(on ? atmo.mute : atmo.faint)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(on ? "Mute cues" : "Unmute cues")
        .accessibilityLabel(on ? "Mute cues" : "Unmute cues")
        .padding(.top, 4)
    }

    private func pinButton(_ atmo: Atmosphere) -> some View {
        Button {
            controller.isPinned.toggle()
        } label: {
            Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                .font(.body.weight(.medium))
                .foregroundStyle(controller.isPinned ? atmo.ink : atmo.faint)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(controller.isPinned ? "Unpin" : "Pin on top")
        .accessibilityLabel(controller.isPinned ? "Unpin" : "Pin on top")
        .padding(.top, 4)
        .padding(.trailing, 8)
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
    @State private var historySnapshot: [CompletedSession] = []

    var body: some View {
        Group {
            if showingHistory {
                HistoryPane(sessions: historySnapshot) {
                    showingHistory = false
                }
            } else {
                VStack(spacing: 14) {
                    Kicker("Intention")
                    HairlineField("What are you doing?", text: $controller.intentionDraft)
                    ScaledClock(Format.clock(0), floor: 18, ceiling: 40, weight: .ultraLight)
                        .foregroundStyle(atmo.faint)
                        .frame(maxHeight: 40)
                        .layoutPriority(0)
                    InkButton("Start") {
                        controller.start()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    HStack(spacing: 16) {
                        Text("Today \(Format.clock(status.todayFocusSeconds))")
                            .foregroundStyle(atmo.faint)
                            .monospacedDigit()
                        Button("History") {
                            historySnapshot = HistoryOrder.newestFirst(controller.world.history)
                            showingHistory = true
                        }
                        .buttonStyle(PressStyle())
                        .foregroundStyle(atmo.mute)
                    }
                    .font(.caption.weight(.medium))
                    GuardConfig(controller: controller)
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
                    .font(.headline)
            }
            if sessions.isEmpty {
                Text("No completed sessions yet.")
                    .font(.body)
                    .foregroundStyle(atmo.mute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions, id: \.id) { session in
                            HistoryRow(session: session)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    @Environment(\.atmosphere) private var atmo
    var session: CompletedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(session.intention.isEmpty ? "No intention" : session.intention)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Format.clock(session.focusSeconds))
                    .font(.body.weight(.medium).monospacedDigit())
            }
            Text(session.endedAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption)
                .foregroundStyle(atmo.faint)
        }
        .padding(10)
        .background(atmo.well)
        .clipShape(RoundedRectangle(cornerRadius: Look.corner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PrimePane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        TimedPane(
            kicker: status.intention,
            progress: ringProgress(status),
            clock: Format.remainingClock(status.remaining ?? 0),
            skip: status.isPaused ? nil : { controller.skip() }
        )
    }
}

private struct FocusPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus
    @FocusState private var captureFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Kicker(status.intention, tracking: 3.4)
            ScaledClock(Format.clock(status.elapsed), floor: 48, ceiling: 112, weight: .ultraLight)
            EarnedStrip(seconds: status.earnedBreakSeconds)
            if let line = controller.guardStatusLine {
                Text(line)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(atmo.faint)
            }
            if let hit = controller.focusGuard.runtime.interception, !status.isPaused {
                Text("\(hit.displayName) is guarded during this Focus.")
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    QuietButton("Stay focused") { controller.stayFocused() }
                    InkButton("Open once") { controller.openOnce() }
                }
            }
            if !status.isPaused {
                if controller.showCapture {
                    HairlineField("Park a thought", text: $controller.captureDraft)
                        .focused($captureFocused)
                        .onSubmit { controller.submitCapture() }
                        .onExitCommand {
                            controller.captureDraft = ""
                            controller.showCapture = false
                        }
                        .onAppear { captureFocused = true }
                } else {
                    Button {
                        controller.showCapture = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.light))
                            .foregroundStyle(atmo.mute)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .help("Park a thought")
                    .accessibilityLabel("Park a thought")
                }
                QuietButton("Stop") { controller.stopFocus() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BreakPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        TimedPane(
            kicker: "This rest was earned",
            progress: ringProgress(status),
            clock: Format.remainingClock(status.remaining ?? 0),
            footnote: "\(Format.clock(status.focusSeconds)) of focus → \(Format.clock(status.phaseDuration ?? 0)) of rest",
            skip: status.isPaused ? nil : { controller.skip() }
        )
    }
}

private struct RecallPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        TimedPane(
            kicker: Format.remainingClock(status.remaining ?? 0),
            heading: "What did you just do?",
            progress: ringProgress(status),
            clock: Format.remainingClock(status.remaining ?? 0),
            skip: status.isPaused ? nil : { controller.skip() }
        ) {
            if !status.isPaused {
                RecallField("One line is enough.", text: $controller.recallDraft)
                    .onChange(of: controller.recallDraft) { _ in
                        controller.persistRecall()
                    }
            } else if !status.recallText.isEmpty {
                Text(status.recallText)
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(atmo.mute)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct CloseBeatPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        let recall = status.recallText.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 10) {
            Kicker("Session")
            VStack(spacing: 0) {
                if !status.intention.isEmpty {
                    ReceiptRow("Intention", value: status.intention)
                }
                ReceiptRow("Focus", value: Format.clock(status.focusSeconds))
                ReceiptRow("Rest taken", value: Format.clock(status.breakSeconds ?? 0))
                if !status.captures.isEmpty {
                    ReceiptRow("Parked", value: "\(status.captures.count)")
                }
                if !recall.isEmpty {
                    ReceiptRow("Recall", value: recall)
                }
            }
            if !status.isPaused {
                Text("Click to dismiss")
                    .font(.caption)
                    .foregroundStyle(atmo.faint)
                QuietButton("Skip") { controller.dismissCloseBeat() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.dismissCloseBeat()
        }
    }
}

/// Timed beats: one hero (clock inside a thin ring). Kicker, footnote, and Skip stay outside.
private struct TimedPane<Extra: View>: View {
    @Environment(\.atmosphere) private var atmo
    var kicker: String
    var heading: String?
    var progress: Double
    var clock: String
    var footnote: String?
    var skip: (() -> Void)?
    var extra: Extra

    init(
        kicker: String,
        heading: String? = nil,
        progress: Double,
        clock: String,
        footnote: String? = nil,
        skip: (() -> Void)?,
        @ViewBuilder extra: () -> Extra
    ) {
        self.kicker = kicker
        self.heading = heading
        self.progress = progress
        self.clock = clock
        self.footnote = footnote
        self.skip = skip
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 10) {
            Kicker(kicker)
            if let heading {
                Text(heading)
                    .font(.system(size: 21, weight: .regular, design: .serif).italic())
                    .foregroundStyle(atmo.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            extra
            ClockInRing(progress: progress, clock: clock)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            if let footnote {
                Text(footnote)
                    .font(.caption.monospacedDigit())
                    .tracking(0.6)
                    .foregroundStyle(atmo.mute)
            }
            if let skip {
                QuietButton("Skip", action: skip)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension TimedPane where Extra == EmptyView {
    init(
        kicker: String,
        heading: String? = nil,
        progress: Double,
        clock: String,
        footnote: String? = nil,
        skip: (() -> Void)?
    ) {
        self.init(
            kicker: kicker,
            heading: heading,
            progress: progress,
            clock: clock,
            footnote: footnote,
            skip: skip,
            extra: { EmptyView() }
        )
    }
}

private struct Kicker: View {
    @Environment(\.atmosphere) private var atmo
    var text: String
    var tracking: CGFloat
    var tone: Tone

    /// Labels whisper by default; a stopped session has to be readable in the Focus cave.
    enum Tone { case faint, mute }

    init(_ text: String, tracking: CGFloat = 2.6, tone: Tone = .faint) {
        self.text = text
        self.tracking = tracking
        self.tone = tone
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .tracking(tracking)
            .foregroundStyle(tone == .faint ? atmo.faint : atmo.mute)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minHeight: 13)
    }
}

private struct ReceiptRow: View {
    @Environment(\.atmosphere) private var atmo
    var label: String
    var value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(atmo.mute)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(atmo.ink)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.footnote)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(atmo.line)
                .frame(height: 1)
        }
    }
}

private struct ClockInRing: View {
    var progress: Double
    var clock: String

    var body: some View {
        GeometryReader { geo in
            let side = min(220, max(72, min(geo.size.width, geo.size.height)))
            ZStack {
                ThinRing(progress: progress)
                ClockText(clock, size: min(36, max(18, side * 0.24)), weight: .ultraLight)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ScaledClock: View {
    var text: String
    var floor: CGFloat
    var ceiling: CGFloat
    var weight: Font.Weight

    init(_ text: String, floor: CGFloat, ceiling: CGFloat, weight: Font.Weight = .light) {
        self.text = text
        self.floor = floor
        self.ceiling = ceiling
        self.weight = weight
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(ceiling, max(floor, min(geo.size.width * 0.26, geo.size.height * 0.72)))
            ClockText(text, size: size, weight: weight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }
}

private struct ClockText: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight

    init(_ text: String, size: CGFloat, weight: Font.Weight = .light) {
        self.text = text
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .default))
            .monospacedDigit()
            .tracking(size >= 28 ? -1.2 : 0)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

/// One hairline under the text. No well, no box: the room is the container.
private struct HairlineField: View {
    @Environment(\.atmosphere) private var atmo
    var placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(atmo.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 2)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(atmo.line)
                    .frame(height: 1)
            }
    }
}

/// Recall is the one written line of the loop, so it gets reading light.
private struct RecallField: View {
    @Environment(\.atmosphere) private var atmo
    var placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .regular, design: .serif).italic())
            .foregroundStyle(atmo.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 2)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(atmo.line)
                    .frame(height: 1)
            }
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The commit action: ink on field, so it inherits the room instead of branding it.
private struct InkButton: View {
    @Environment(\.atmosphere) private var atmo
    @Environment(\.isEnabled) private var isEnabled
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(minWidth: 72)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(atmo.ink)
                .foregroundStyle(atmo.field)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressStyle())
    }
}

private struct QuietButton: View {
    @Environment(\.atmosphere) private var atmo
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(atmo.mute)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .overlay(
                    Capsule().stroke(atmo.line, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Timed phases keep a hairline ring: the room's own line, filled with its own mid tone.
private struct ThinRing: View {
    @Environment(\.atmosphere) private var atmo
    var progress: Double
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(atmo.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(atmo.mute, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// The only warm mark in the app. Focus is otherwise black and white.
private struct EarnedStrip: View {
    @Environment(\.atmosphere) private var atmo
    var seconds: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            if seconds >= 1 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(atmo.line)
                        Capsule()
                            .fill(Atmosphere.rest)
                            .frame(width: max(2, geo.size.width * stripFill))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 12)
                Text(Format.earned(seconds))
                    .font(.caption.monospacedDigit())
                    .tracking(0.6)
                    .foregroundStyle(atmo.mute)
            }
        }
        .frame(minHeight: 20)
    }

    /// Ten minutes of earned rest fills the strip; past that the label carries the number.
    private var stripFill: Double {
        min(1, max(0, seconds / 600))
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
                    .font(.caption.weight(.medium))
                    .foregroundStyle(atmo.mute)
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
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("Remove") {
                            controller.removeGuardedApp(bundleIdentifier: id)
                        }
                        .buttonStyle(PressStyle())
                        .font(.caption.weight(.medium))
                        .foregroundStyle(atmo.mute)
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
