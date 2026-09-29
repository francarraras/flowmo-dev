import FlowmoCore
import SwiftUI

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
        red: 214 / 255,
        green: 184 / 255,
        blue: 137 / 255,
        opacity: 1
    )

    public static let restDeep = Color(
        .sRGB,
        red: 132 / 255,
        green: 110 / 255,
        blue: 78 / 255,
        opacity: 1
    )

    public static let canvas = Atmosphere(
        field: hex(0x090A0C),
        ink: hex(0xF3F1EA),
        mute: hex(0xAAA9A4),
        faint: hex(0x898A87),
        line: hex(0x1C1E21),
        track: hex(0x34373A),
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
    /// A quiet transition between states; the instrument stays in place.
    public static let phase: Animation = .easeInOut(duration: 0.24)
    /// Press feedback changes tone, never size.
    public static let press: Animation = .easeOut(duration: 0.10)
    /// Hover and keyboard focus share one restrained response.
    public static let hover: Animation = .easeOut(duration: 0.16)
    /// The horizon's light changes phase: a dawn that rises or sets, never snaps.
    public static let light: Animation = .easeInOut(duration: 0.6)
}

extension View {
    /// Liquid Glass where the platform offers it (macOS 26 / iOS 26). Glass is
    /// for controls and chrome only; the graphite field and the horizon remain
    /// the identity. Older systems keep the caller's own surface, so nothing
    /// there changes. Glass follows Reduce Transparency and Increase Contrast.
    @ViewBuilder
    public func instrumentSurface<Fallback: View>(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(
                tint.map { Glass.regular.tint($0) } ?? .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(fallback())
        }
    }

    /// Capsule glass for a small group of chrome icons, or nothing on older systems.
    @ViewBuilder
    public func chromeSurface() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
        }
    }
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
    public static let corner: CGFloat = 14
}
