import SwiftUI
import FlowmoCore

struct FlowmoRootView: View {
    @ObservedObject var controller: FlowmoSessionController

    var body: some View {
        let status = controller.status
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button {
                    controller.isPinned.toggle()
                } label: {
                    Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .help(controller.isPinned ? "Unpin" : "Pin on top")
                .accessibilityLabel(controller.isPinned ? "Unpin" : "Pin on top")
            }

            Group {
                if status.isIdle {
                    IdlePane(controller: controller, status: status)
                } else {
                    phasePane(status)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if status.isPaused {
                Button("Continue") {
                    controller.continueSession()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 260, minHeight: 340)
        .background(WindowPin(pinned: controller.isPinned))
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
        VStack(spacing: 16) {
            Text(Format.clock(0))
                .font(.system(size: 44, weight: .light, design: .monospaced))
            TextField("Intention", text: $controller.intentionDraft)
                .textFieldStyle(.roundedBorder)
            Button("Start") {
                controller.start()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Today \(Format.clock(status.todayFocusSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrimePane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        VStack(spacing: 14) {
            Text(status.intention)
                .multilineTextAlignment(.center)
            DeterminateRing(progress: ringProgress(status))
            Text(Format.remainingClock(status.remaining ?? 0))
                .font(.system(size: 28, weight: .light, design: .monospaced))
            if !status.isPaused {
                Button("Skip") { controller.skip() }
            }
        }
    }
}

private struct FocusPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus
    @FocusState private var captureFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(Format.clock(status.elapsed))
                .font(.system(size: 48, weight: .light, design: .monospaced))
            EarnedStrip(seconds: status.earnedBreakSeconds)
            if !status.isPaused {
                if controller.showCapture {
                    TextField("Park a thought", text: $controller.captureDraft)
                        .textFieldStyle(.roundedBorder)
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
                    }
                    .buttonStyle(.plain)
                    .help("Park a thought")
                    .accessibilityLabel("Park a thought")
                }
                Button("Stop") { controller.stopFocus() }
            }
        }
    }
}

private struct BreakPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        VStack(spacing: 14) {
            Text("This rest was earned")
                .multilineTextAlignment(.center)
            DeterminateRing(progress: ringProgress(status))
            Text(Format.remainingClock(status.remaining ?? 0))
                .font(.system(size: 28, weight: .light, design: .monospaced))
            if !status.isPaused {
                Button("Skip") { controller.skip() }
            }
        }
    }
}

private struct RecallPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        VStack(spacing: 14) {
            Text("What did you just do?")
                .multilineTextAlignment(.center)
            if !status.isPaused {
                TextField("Optional", text: $controller.recallDraft)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: controller.recallDraft) { _ in
                        controller.persistRecall()
                    }
            } else if !status.recallText.isEmpty {
                Text(status.recallText)
                    .foregroundStyle(.secondary)
            }
            DeterminateRing(progress: ringProgress(status))
            Text(Format.remainingClock(status.remaining ?? 0))
                .font(.system(size: 28, weight: .light, design: .monospaced))
            if !status.isPaused {
                Button("Skip") { controller.skip() }
            }
        }
    }
}

private struct CloseBeatPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        let recall = status.recallText.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 12) {
            Text("Focus \(Format.clock(status.focusSeconds))")
            Text("Break \(Format.clock(status.breakSeconds ?? 0))")
            if !recall.isEmpty {
                Text(recall)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !status.isPaused {
                Text("Click to dismiss")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Skip") { controller.dismissCloseBeat() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.dismissCloseBeat()
        }
    }
}

private struct DeterminateRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 112, height: 112)
    }
}

private struct EarnedStrip: View {
    var seconds: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            if seconds >= 1 {
                Capsule()
                    .fill(Color.primary.opacity(0.7))
                    .frame(width: min(220, max(2, CGFloat(seconds / 60) * 28)), height: 4)
                Text(Format.earned(seconds))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 28)
    }
}

private func ringProgress(_ status: SessionStatus) -> Double {
    guard let duration = status.phaseDuration, duration > 0 else { return 0 }
    return min(1, max(0, status.elapsed / duration))
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
    }
}
