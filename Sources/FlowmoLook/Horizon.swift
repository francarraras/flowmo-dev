import FlowmoCore
import SwiftUI

/// The numbers behind the Distant Horizon, in one place. None of them is a
/// deadline: Focus values grow without a ceiling, and timed phases reuse the
/// same progress the aperture ring already shows.
public enum HorizonTuning {
    /// Planet rotation in degrees per focused hour. Open-ended; no target angle.
    public static let turnDegreesPerHour: Double = 30
    /// Minutes of earned rest at which the dawn is 63% champagne.
    public static let warmthMinutes: Double = 12
    /// Hours of Focus at which the dawn's lateral travel reaches 63% of its reach.
    public static let travelHours: Double = 2
    /// Light at Idle and Close Beat: a hairline of pre-dawn.
    public static let dawn: Double = 0.10
    /// Light when Break ends and Reflection begins.
    public static let dusk: Double = 0.26
    /// Limb height as a fraction of the canvas.
    public static let arcY: Double = 0.62
    /// Planet radius as a multiple of the canvas width. Smaller is rounder.
    public static let curvature: Double = 1.2
    /// Surface relief contrast, 0 = polished obsidian, 1 = rugged.
    public static let relief: Double = 0.6
    /// Aerial haze where the far surface melts into the atmosphere.
    public static let haze: Double = 1.0
    /// Film grain amount.
    public static let grain: Double = 0.016
    /// Star density per 44pt sky cell. 0 removes them.
    public static let stars: Double = 0.12
    /// Ambient frames per second while the scene is live. State changes redraw regardless.
    public static let ambientFramesPerSecond: Double = 15
}

/// What the Distant Horizon shows. A pure projection of `SessionStatus`; it has
/// no clock of its own and is never persisted. Focus shows only open-ended
/// quantities (focused time, earned rest). Prime, Break, and Reflection show
/// their determinate progress, as the aperture ring already does.
public struct HorizonState: Equatable, Sendable {
    /// 0…1 how far the dawn has risen at the horizon.
    public var light: Double
    /// 0…1 champagne share of that light: rest earned so far, or still to be taken. Never a fill.
    public var warmth: Double
    /// Planet rotation in radians from focused time. Unbounded; no target.
    public var turn: Double
    /// 0…1 asymptotic lateral travel of the dawn along the limb with focused time.
    public var travel: Double
    /// Recovery Pause: exact values, no ambient motion.
    public var frozen: Bool

    public init(light: Double, warmth: Double, turn: Double, travel: Double, frozen: Bool) {
        self.light = light
        self.warmth = warmth
        self.turn = turn
        self.travel = travel
        self.frozen = frozen
    }

    public static let idle = HorizonState(light: HorizonTuning.dawn, warmth: 0, turn: 0, travel: 0, frozen: false)

    public static func warmth(earned: TimeInterval) -> Double {
        1 - exp(-max(0, earned) / (HorizonTuning.warmthMinutes * 60))
    }

    public static func travel(focus: TimeInterval) -> Double {
        1 - exp(-max(0, focus) / (HorizonTuning.travelHours * 3600))
    }

    public static func turn(focus: TimeInterval) -> Double {
        max(0, focus) / 3600 * HorizonTuning.turnDegreesPerHour * .pi / 180
    }

    static func progress(_ status: SessionStatus) -> Double {
        guard let duration = status.phaseDuration, duration > 0 else { return 0 }
        return min(1, max(0, status.elapsed / duration))
    }

    public static func of(_ status: SessionStatus) -> HorizonState {
        let dawn = HorizonTuning.dawn
        let dusk = HorizonTuning.dusk
        let turn = turn(focus: status.focusSeconds)
        let travel = travel(focus: status.focusSeconds)
        let progress = progress(status)
        switch status.phase {
        case nil:
            return .idle
        case .prime:
            // Settling: the dawn gathers at the horizon over Prime.
            return HorizonState(
                light: dawn + (1 - dawn) * progress, warmth: 0, turn: 0, travel: 0, frozen: status.isPaused)
        case .focus:
            // Open-ended: full dawn, planet turns with time, champagne grows with earned rest.
            return HorizonState(
                light: 1, warmth: warmth(earned: status.earnedBreakSeconds),
                turn: turn, travel: travel, frozen: status.isPaused)
        case .onBreak:
            // Rest is spent: the dawn sets over the countdown and the champagne drains with it.
            let earned = warmth(earned: status.earnedBreakSeconds)
            return HorizonState(
                light: 1 - (1 - dusk) * progress, warmth: earned * (1 - progress),
                turn: turn, travel: travel, frozen: status.isPaused)
        case .recall:
            return HorizonState(
                light: dusk - (dusk - dawn) * progress, warmth: 0,
                turn: turn, travel: travel, frozen: status.isPaused)
        case .closeBeat:
            return HorizonState(light: dawn, warmth: 0, turn: turn, travel: travel, frozen: status.isPaused)
        }
    }
}

extension HorizonState: Animatable {
    /// Light, warmth, turn, and travel ease between values; `frozen` switches.
    public var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { AnimatablePair(AnimatablePair(light, warmth), AnimatablePair(turn, travel)) }
        set {
            light = newValue.first.first
            warmth = newValue.first.second
            turn = newValue.second.first
            travel = newValue.second.second
        }
    }
}

private struct HorizonStateKey: EnvironmentKey {
    static let defaultValue = HorizonState.idle
}

extension EnvironmentValues {
    /// The current session's horizon, for the compact aperture rim and field.
    public var horizon: HorizonState {
        get { self[HorizonStateKey.self] }
        set { self[HorizonStateKey.self] = newValue }
    }
}
