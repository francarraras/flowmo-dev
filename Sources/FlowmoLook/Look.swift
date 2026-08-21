import SwiftUI
import FlowmoCore

/// Phase atmosphere: one frame, six rooms.
/// Nothing is added between phases — the same elements change temperature.
/// The engine never sees this; only contrast, chrome, and warmth move.
public struct Atmosphere: Equatable, Sendable {
    /// Room. The window background.
    public let field: Color
    /// The one thing you are meant to read.
    public let ink: Color
    /// Supporting text and the timed ring.
    public let mute: Color
    /// Labels that should not compete.
    public let faint: Color
    /// Hairlines: field underlines, ring tracks, receipt rules.
    public let line: Color
    /// How present the window furniture (mute, pin) is allowed to be.
    public let chrome: Double

    public init(
        field: Color,
        ink: Color,
        mute: Color,
        faint: Color,
        line: Color,
        chrome: Double
    ) {
        self.field = field
        self.ink = ink
        self.mute = mute
        self.faint = faint
        self.line = line
        self.chrome = chrome
    }

    /// Filled wells (history rows) stay at hairline weight.
    public var well: Color { line }

    /// Earned rest. The only warm mark in the app, and only on the earned strip.
    public static let rest = hex(0xC8A24B)

    /// Dry and neutral. Intention leads, the clock recedes.
    public static let idle = Atmosphere(
        field: hex(0x0A0B0D),
        ink: hex(0xDDDEE1),
        mute: hex(0x6E747D),
        faint: hex(0x3A3F47),
        line: hex(0x1B1E23),
        chrome: 1
    )

    /// Still and low contrast. Nothing asks for a decision yet.
    public static let prime = Atmosphere(
        field: hex(0x08090C),
        ink: hex(0x9BA0A8),
        mute: hex(0x4A4F57),
        faint: hex(0x2A2E35),
        line: hex(0x16181D),
        chrome: 0.45
    )

    /// Black room, one moving color. Chrome nearly disappears.
    public static let focus = Atmosphere(
        field: hex(0x000000),
        ink: hex(0xFFFFFF),
        mute: hex(0x585D66),
        faint: hex(0x2A2E35),
        line: hex(0x15171B),
        chrome: 0.25
    )

    /// Softer and warmer. The room itself is the reward.
    public static let onBreak = Atmosphere(
        field: hex(0x12100C),
        ink: hex(0xD9CFC0),
        mute: hex(0x77705F),
        faint: hex(0x44403A),
        line: hex(0x211E18),
        chrome: 0.8
    )

    /// Editorial. Reading light for one written line.
    public static let recall = Atmosphere(
        field: hex(0x0C0D10),
        ink: hex(0xE9EAEC),
        mute: hex(0x7C828B),
        faint: hex(0x3A3F47),
        line: hex(0x1D2026),
        chrome: 1
    )

    /// The receipt returns to the idle room, because that is where it leaves you.
    public static let close = idle

    public static func of(_ status: SessionStatus) -> Atmosphere {
        of(status.phase)
    }

    public static func of(_ phase: SessionPhase?) -> Atmosphere {
        switch phase {
        case .prime: return .prime
        case .focus: return .focus
        case .onBreak: return .onBreak
        case .recall: return .recall
        case .closeBeat: return .close
        case nil: return .idle
        }
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

private struct AtmosphereKey: EnvironmentKey {
    static let defaultValue = Atmosphere.idle
}

extension EnvironmentValues {
    /// Set once at the root of each app from the live phase; every pane reads it.
    public var atmosphere: Atmosphere {
        get { self[AtmosphereKey.self] }
        set { self[AtmosphereKey.self] = newValue }
    }
}

/// Idle aliases. Kept so non-session surfaces have one ink without reaching for a phase.
public enum Look {
    public static let field = Atmosphere.idle.field
    public static let ink = Atmosphere.idle.ink
    public static let mute = Atmosphere.idle.mute
    public static let dim = Atmosphere.idle.faint
    public static let line = Atmosphere.idle.line
    public static let well = Atmosphere.idle.well
    public static let rest = Atmosphere.rest

    public static let accent = Atmosphere.idle.ink
    public static let action = accent
    public static let time = Atmosphere.idle.mute
    public static let ringTrack = Atmosphere.idle.line
    public static let corner: CGFloat = 8
}
