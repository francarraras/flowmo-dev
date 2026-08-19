import AppKit
import UniformTypeIdentifiers
import SwiftUI
import FlowmoCore

private enum Look {
    static let field = Color.black
    static let ink = Color.white
    static let mute = Color.white.opacity(0.72)
    static let dim = Color.white.opacity(0.42)
    static let accent = Color.cyan
    static let well = Color.white.opacity(0.08)
}

struct FlowmoRootView: View {
    @ObservedObject var controller: FlowmoSessionController

    var body: some View {
        let status = controller.status
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
                AccentButton("Continue") {
                    controller.continueSession()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Look.ink)
        .background(Look.field)
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            pinButton
        }
        .background(WindowPin(pinned: controller.isPinned))
    }

    private var pinButton: some View {
        Button {
            controller.isPinned.toggle()
        } label: {
            Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                .font(.body.weight(.medium))
                .foregroundStyle(controller.isPinned ? Look.accent : Look.mute)
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
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        VStack(spacing: 12) {
            ScaledClock(Format.clock(0), floor: 32, ceiling: 64)
            DarkField("Intention", text: $controller.intentionDraft)
            AccentButton("Start") {
                controller.start()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Today \(Format.clock(status.todayFocusSeconds))")
                .font(.caption.weight(.medium))
                .foregroundStyle(Look.dim)
            GuardConfig(controller: controller)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PrimePane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        TimedPane(
            caption: status.intention,
            progress: ringProgress(status),
            clock: Format.remainingClock(status.remaining ?? 0),
            skip: status.isPaused ? nil : { controller.skip() }
        )
    }
}

private struct FocusPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus
    @FocusState private var captureFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            ScaledClock(Format.clock(status.elapsed), floor: 36, ceiling: 72)
            EarnedStrip(seconds: status.earnedBreakSeconds)
            if let line = controller.guardStatusLine {
                Text(line)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Look.dim)
            }
            if let hit = controller.focusGuard.runtime.interception, !status.isPaused {
                Text("\(hit.displayName) is guarded during this Focus.")
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    QuietButton("Stay focused") { controller.stayFocused() }
                    AccentButton("Open once") { controller.openOnce() }
                }
            }
            if !status.isPaused {
                if controller.showCapture {
                    DarkField("Park a thought", text: $controller.captureDraft)
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
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Look.accent)
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
            caption: "This rest was earned",
            mutedCaption: true,
            progress: ringProgress(status),
            clock: Format.remainingClock(status.remaining ?? 0),
            skip: status.isPaused ? nil : { controller.skip() }
        )
    }
}

private struct RecallPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        TimedPane(
            caption: "What did you just do?",
            progress: ringProgress(status),
            clock: Format.remainingClock(status.remaining ?? 0),
            skip: status.isPaused ? nil : { controller.skip() }
        ) {
            if !status.isPaused {
                DarkField("Optional", text: $controller.recallDraft)
                    .onChange(of: controller.recallDraft) { _ in
                        controller.persistRecall()
                    }
            } else if !status.recallText.isEmpty {
                Text(status.recallText)
                    .foregroundStyle(Look.mute)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct CloseBeatPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        let recall = status.recallText.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 8) {
            Text("Focus \(Format.clock(status.focusSeconds))")
                .font(.body.weight(.medium).monospacedDigit())
            Text("Break \(Format.clock(status.breakSeconds ?? 0))")
                .font(.body.weight(.medium).monospacedDigit())
            if !recall.isEmpty {
                Text(recall)
                    .foregroundStyle(Look.mute)
                    .multilineTextAlignment(.center)
            }
            if !status.isPaused {
                Text("Click to dismiss")
                    .font(.caption)
                    .foregroundStyle(Look.dim)
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

/// Timed beats: one hero (clock inside the ring). Caption and Skip stay outside.
private struct TimedPane<Extra: View>: View {
    var caption: String
    var mutedCaption: Bool = false
    var progress: Double
    var clock: String
    var skip: (() -> Void)?
    var extra: Extra

    init(
        caption: String,
        mutedCaption: Bool = false,
        progress: Double,
        clock: String,
        skip: (() -> Void)?,
        @ViewBuilder extra: () -> Extra
    ) {
        self.caption = caption
        self.mutedCaption = mutedCaption
        self.progress = progress
        self.clock = clock
        self.skip = skip
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(caption)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .foregroundStyle(mutedCaption ? Look.mute : Look.ink)
            extra
            ClockInRing(progress: progress, clock: clock)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            if let skip {
                QuietButton("Skip", action: skip)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension TimedPane where Extra == EmptyView {
    init(
        caption: String,
        mutedCaption: Bool = false,
        progress: Double,
        clock: String,
        skip: (() -> Void)?
    ) {
        self.init(
            caption: caption,
            mutedCaption: mutedCaption,
            progress: progress,
            clock: clock,
            skip: skip,
            extra: { EmptyView() }
        )
    }
}

private struct ClockInRing: View {
    var progress: Double
    var clock: String

    var body: some View {
        GeometryReader { geo in
            let side = min(220, max(72, min(geo.size.width, geo.size.height)))
            ZStack {
                DeterminateRing(progress: progress, lineWidth: max(4, side * 0.055))
                ClockText(clock, size: min(36, max(18, side * 0.24)))
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

    init(_ text: String, floor: CGFloat, ceiling: CGFloat) {
        self.text = text
        self.floor = floor
        self.ceiling = ceiling
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(ceiling, max(floor, min(geo.size.width * 0.22, geo.size.height * 0.72)))
            ClockText(text, size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }
}

private struct ClockText: View {
    var text: String
    var size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .light, design: .default))
            .monospacedDigit()
            .tracking(size >= 28 ? -0.8 : 0)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

private struct DarkField: View {
    var placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Look.well)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct AccentButton: View {
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
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Look.accent)
                .foregroundStyle(Look.field)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

private struct QuietButton: View {
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Look.mute)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

private struct DeterminateRing: View {
    var progress: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Look.ink.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Look.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

private struct EarnedStrip: View {
    var seconds: TimeInterval

    var body: some View {
        VStack(spacing: 6) {
            if seconds >= 1 {
                Capsule()
                    .fill(Look.accent)
                    .frame(width: min(160, max(2, CGFloat(seconds / 60) * 28)), height: 3)
                Text(Format.earned(seconds))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Look.mute)
            }
        }
        .frame(minHeight: 20)
    }
}

private func ringProgress(_ status: SessionStatus) -> Double {
    guard let duration = status.phaseDuration, duration > 0 else { return 0 }
    return min(1, max(0, status.elapsed / duration))
}


private struct GuardConfig: View {
    @ObservedObject var controller: FlowmoSessionController

    var body: some View {
        let config = controller.world.config.focusGuard
        VStack(spacing: 6) {
            Button {
                controller.showGuardConfig.toggle()
            } label: {
                Text(guardLabel(config))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Look.mute)
            }
            .buttonStyle(PressStyle())
            if controller.showGuardConfig {
                Toggle("On", isOn: Binding(
                    get: { config.enabled },
                    set: { controller.setGuardEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Look.accent)
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
                        .foregroundStyle(Look.mute)
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

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.level = pinned ? .floating : .normal
        window.hidesOnDeactivate = false
        window.backgroundColor = .black
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
