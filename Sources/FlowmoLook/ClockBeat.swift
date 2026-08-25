import FlowmoCore
import SwiftUI

/// Short grow when the count-up crosses a mark. Ink only — gold stays earned rest.
public struct MilestoneGrow: ViewModifier {
    var elapsed: TimeInterval
    var paused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastElapsed: TimeInterval
    @State private var scale: CGFloat = 1

    public init(elapsed: TimeInterval, paused: Bool) {
        self.elapsed = elapsed
        self.paused = paused
        _lastElapsed = State(initialValue: elapsed)
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: elapsed) { _, now in
                let from = lastElapsed
                lastElapsed = now
                guard !paused, !reduceMotion else { return }
                guard ClockMarks.crossing(from: from, to: now) != nil else { return }
                pulse(to: 1.16, hold: 0.20)
            }
    }

    private func pulse(to peak: CGFloat, hold: TimeInterval) {
        withAnimation(Motion.mark) { scale = peak }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            withAnimation(Motion.markSettle) { scale = 1 }
        }
    }
}

/// Break open bloom, then a last-10s pulse as the next focus comes up.
public struct BreakRace: ViewModifier {
    var remaining: TimeInterval
    var elapsed: TimeInterval
    var paused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastSecond: Int = -1
    @State private var opened = false

    public init(remaining: TimeInterval, elapsed: TimeInterval, paused: Bool) {
        self.remaining = remaining
        self.elapsed = elapsed
        self.paused = paused
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear { openBeat() }
            .onChange(of: remaining) { _, now in
                raceTick(now)
            }
    }

    private func openBeat() {
        guard !opened else { return }
        opened = true
        guard !reduceMotion, !paused, elapsed < 2 else { return }
        pulse(to: 1.14, hold: 0.24)
    }

    private func raceTick(_ now: TimeInterval) {
        guard !paused, !reduceMotion else { return }
        guard now > 0, now <= 10 else { return }
        let sec = Format.remainingSeconds(now)
        guard sec != lastSecond, sec >= 1, sec <= 10 else { return }
        lastSecond = sec
        pulse(to: 1.09, hold: 0.14)
    }

    private func pulse(to peak: CGFloat, hold: TimeInterval) {
        withAnimation(Motion.race) { scale = peak }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            withAnimation(Motion.markSettle) { scale = 1 }
        }
    }
}

extension View {
    public func milestoneGrow(elapsed: TimeInterval, paused: Bool) -> some View {
        modifier(MilestoneGrow(elapsed: elapsed, paused: paused))
    }

    public func breakRace(remaining: TimeInterval, elapsed: TimeInterval, paused: Bool) -> some View {
        modifier(BreakRace(remaining: remaining, elapsed: elapsed, paused: paused))
    }
}
