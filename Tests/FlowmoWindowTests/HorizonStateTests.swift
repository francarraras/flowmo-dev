import FlowmoCore
import FlowmoLook
import XCTest

/// The Distant Horizon is a picture of the session, never a second clock. These
/// proofs pin the rules: Focus has no ceiling or finish line, timed phases
/// reuse Core's progress, and Recovery Pause freezes the exact values.
final class HorizonStateTests: XCTestCase {
    private func status(
        phase: SessionPhase?, paused: Bool = false, elapsed: TimeInterval = 0, duration: TimeInterval? = nil,
        focus: TimeInterval = 0, earned: TimeInterval = 0
    ) -> SessionStatus {
        SessionStatus(
            phase: phase, isPaused: paused, intention: "", lastIntention: "", elapsed: elapsed, remaining: nil,
            phaseDuration: duration, focusSeconds: focus, breakSeconds: nil, earnedBreakSeconds: earned,
            captures: [], recallText: "", todayFocusSeconds: 0, ratio: 5)
    }

    func testIdleIsAPreDawnHairlineWithNoWarmthOrTurn() {
        let idle = HorizonState.of(status(phase: nil))
        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(idle.light, HorizonTuning.dawn)
        XCTAssertEqual(idle.warmth, 0)
        XCTAssertEqual(idle.turn, 0)
        XCTAssertFalse(idle.frozen)
    }

    func testPrimeRisesWithCoreProgressAndNothingElse() {
        let start = HorizonState.of(status(phase: .prime, elapsed: 0, duration: 120))
        let half = HorizonState.of(status(phase: .prime, elapsed: 60, duration: 120))
        let end = HorizonState.of(status(phase: .prime, elapsed: 120, duration: 120))
        XCTAssertEqual(start.light, HorizonTuning.dawn, accuracy: 1e-9)
        XCTAssertEqual(half.light, HorizonTuning.dawn + (1 - HorizonTuning.dawn) / 2, accuracy: 1e-9)
        XCTAssertEqual(end.light, 1, accuracy: 1e-9)
        XCTAssertEqual(half.warmth, 0)
        XCTAssertEqual(half.turn, 0)
        // Past the duration clamps like the ring does.
        XCTAssertEqual(HorizonState.of(status(phase: .prime, elapsed: 900, duration: 120)).light, 1, accuracy: 1e-9)
    }

    func testFocusHasFullLightAndOpenEndedGrowthWithNoCeiling() {
        let ten = HorizonState.of(status(phase: .focus, elapsed: 600, focus: 600, earned: 120))
        let fifty = HorizonState.of(status(phase: .focus, elapsed: 3000, focus: 3000, earned: 600))
        let fiveHours = HorizonState.of(status(phase: .focus, elapsed: 18000, focus: 18000, earned: 3600))
        for state in [ten, fifty, fiveHours] {
            XCTAssertEqual(state.light, 1)
            XCTAssertFalse(state.frozen)
        }
        // Earned rest warms the dawn monotonically and never reaches a fill.
        XCTAssertLessThan(ten.warmth, fifty.warmth)
        XCTAssertLessThan(fifty.warmth, fiveHours.warmth)
        XCTAssertLessThan(fiveHours.warmth, 1)
        // Focused time turns the planet without bound.
        XCTAssertLessThan(ten.turn, fifty.turn)
        XCTAssertLessThan(fifty.turn, fiveHours.turn)
        XCTAssertGreaterThan(fiveHours.turn, 2 * .pi / 3)
        // Travel is bounded so the dawn never leaves the canvas.
        XCTAssertLessThan(fiveHours.travel, 1)
        XCTAssertGreaterThan(fiveHours.travel, fifty.travel)
    }

    func testBreakSetsTheDawnAndDrainsExactlyTheEarnedWarmth() {
        let earned: TimeInterval = 600
        let start = HorizonState.of(status(phase: .onBreak, elapsed: 0, duration: earned, focus: 3000, earned: earned))
        let half = HorizonState.of(status(phase: .onBreak, elapsed: 300, duration: earned, focus: 3000, earned: earned))
        let end = HorizonState.of(status(phase: .onBreak, elapsed: 600, duration: earned, focus: 3000, earned: earned))
        let focusEnd = HorizonState.of(status(phase: .focus, elapsed: 3000, focus: 3000, earned: earned))
        XCTAssertEqual(start.light, 1, accuracy: 1e-9)
        XCTAssertEqual(start.warmth, focusEnd.warmth, accuracy: 1e-9)
        XCTAssertEqual(half.warmth, focusEnd.warmth / 2, accuracy: 1e-9)
        XCTAssertEqual(end.warmth, 0, accuracy: 1e-9)
        XCTAssertEqual(end.light, HorizonTuning.dusk, accuracy: 1e-9)
        XCTAssertGreaterThan(start.light, half.light)
        XCTAssertGreaterThan(half.light, end.light)
        // The planet keeps the angle it reached; Break does not turn it further.
        XCTAssertEqual(start.turn, focusEnd.turn)
        XCTAssertEqual(end.turn, focusEnd.turn)
    }

    func testReflectionSettlesToDawnAndCloseBeatRestsThere() {
        let start = HorizonState.of(status(phase: .recall, elapsed: 0, duration: 180, focus: 3000))
        let end = HorizonState.of(status(phase: .recall, elapsed: 180, duration: 180, focus: 3000))
        let close = HorizonState.of(status(phase: .closeBeat, focus: 3000))
        XCTAssertEqual(start.light, HorizonTuning.dusk, accuracy: 1e-9)
        XCTAssertEqual(end.light, HorizonTuning.dawn, accuracy: 1e-9)
        XCTAssertEqual(close.light, HorizonTuning.dawn, accuracy: 1e-9)
        XCTAssertEqual(start.warmth, 0)
        XCTAssertEqual(close.warmth, 0)
    }

    func testRecoveryPauseFreezesExactValuesInEveryLivePhase() {
        let cases: [(SessionPhase, TimeInterval?)] = [(.prime, 120), (.focus, nil), (.onBreak, 600), (.recall, 180)]
        for (phase, duration) in cases {
            let running = HorizonState.of(
                status(phase: phase, elapsed: 45, duration: duration, focus: 3000, earned: 600))
            let paused = HorizonState.of(
                status(phase: phase, paused: true, elapsed: 45, duration: duration, focus: 3000, earned: 600))
            XCTAssertFalse(running.frozen, "\(phase)")
            XCTAssertTrue(paused.frozen, "\(phase)")
            XCTAssertEqual(paused.light, running.light, "\(phase)")
            XCTAssertEqual(paused.warmth, running.warmth, "\(phase)")
            XCTAssertEqual(paused.turn, running.turn, "\(phase)")
        }
    }

    func testEveryValueStaysInsideItsRangeAcrossTheLoop() {
        let samples: [SessionStatus] = [
            status(phase: nil),
            status(phase: .prime, elapsed: 30, duration: 120),
            status(phase: .focus, elapsed: 7 * 3600, focus: 7 * 3600, earned: 7 * 720),
            status(phase: .onBreak, elapsed: 100, duration: 600, focus: 3000, earned: 600),
            status(phase: .recall, elapsed: 100, duration: 180, focus: 3000),
            status(phase: .closeBeat, focus: 3000),
            status(phase: .prime, elapsed: -5, duration: 0),
        ]
        for sample in samples {
            let state = HorizonState.of(sample)
            XCTAssert((0...1).contains(state.light), "light \(state.light) for \(String(describing: sample.phase))")
            XCTAssert((0...1).contains(state.warmth), "warmth \(state.warmth)")
            XCTAssert((0...1).contains(state.travel), "travel \(state.travel)")
            XCTAssertGreaterThanOrEqual(state.turn, 0)
        }
    }
}
