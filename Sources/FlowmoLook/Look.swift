import SwiftUI
import FlowmoCore

/// One charcoal square. Phase is the aperture, not the wallpaper.
public struct Atmosphere: Equatable, Sendable {
    public var field: Color
    public var ink: Color
    public var mute: Color
    public var faint: Color
    public var line: Color
    public var track: Color
    public var chrome: Double

    public var well: Color { line }

    /// Warm metal. The only chromatic object besides ink.
    public static let rest = Color(
        .sRGB,
        red: 232 / 255,
        green: 186 / 255,
        blue: 92 / 255,
        opacity: 1
    )

    public static let restDeep = Color(
        .sRGB,
        red: 168 / 255,
        green: 118 / 255,
        blue: 42 / 255,
        opacity: 1
    )

    public static let canvas = Atmosphere(
        field: hex(0x090A0C),
        ink: hex(0xF3F1EA),
        mute: hex(0x9A958A),
        faint: hex(0x4A4842),
        line: hex(0x1C1B18),
        track: hex(0x32302C),
        chrome: 1
    )

    public static func of(_ status: SessionStatus) -> Atmosphere {
        of(status.phase)
    }

    public static func of(_ phase: SessionPhase?) -> Atmosphere {
        var room = canvas
        if phase == .focus {
            room.chrome = 0.35
        }
        return room
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

public enum Motion {
    /// Captions and verbs ease in the same slot. The circle does not travel.
    public static let phase: Animation = .easeOut(duration: 0.28)
    /// Pieces click together. Inverse of a blast.
    public static let assemble: Animation = .spring(response: 0.48, dampingFraction: 0.82)
    /// Ring or hole leaving. Fade in place.
    public static let dissolve: Animation = .easeOut(duration: 0.20)
    /// Clock digits and ring trim while live.
    public static let tick: Animation = .easeInOut(duration: 0.28)
    /// Accrual growth.
    public static let rest: Animation = .spring(response: 0.7, dampingFraction: 0.9)
    /// Press.
    public static let press: Animation = .easeOut(duration: 0.12)
    /// Quiet text / chrome lifts on hover.
    public static let hover: Animation = .easeOut(duration: 0.16)
    /// Idle ring breathe.
    public static let breathe: Animation = .easeInOut(duration: 3.6).repeatForever(autoreverses: true)
    /// Focus mark grow (5 / 10 / 15 / 30 / 45 / 60).
    public static let mark: Animation = .spring(response: 0.28, dampingFraction: 0.55)
    /// Settle after a grow.
    public static let markSettle: Animation = .spring(response: 0.42, dampingFraction: 0.78)
    /// Break last-10s race pulse.
    public static let race: Animation = .spring(response: 0.22, dampingFraction: 0.62)
    /// Lunar face inside the aperture. Light stays put; the surface turns.
    public static let moon: Animation = .linear(duration: 96).repeatForever(autoreverses: false)
}

private struct AtmosphereKey: EnvironmentKey {
    static let defaultValue = Atmosphere.canvas
}


extension EnvironmentValues {
    public var atmosphere: Atmosphere {
        get { self[AtmosphereKey.self] }
        set { self[AtmosphereKey.self] = newValue }
    }
}

public enum Look {
    public static let field = Atmosphere.canvas.field
    public static let ink = Atmosphere.canvas.ink
    public static let mute = Atmosphere.canvas.mute
    public static let dim = Atmosphere.canvas.faint
    public static let faint = Atmosphere.canvas.faint
    public static let line = Atmosphere.canvas.line
    public static let well = Atmosphere.canvas.well
    public static let rest = Atmosphere.rest
    public static let accent = Atmosphere.canvas.ink
    public static let action = accent
    public static let time = Atmosphere.canvas.mute
    public static let ringTrack = Atmosphere.canvas.track
    public static let corner: CGFloat = 8
}
