import SwiftUI

/// Semantic visual tokens for the compact session frame.
/// Same ink on Mac and iPhone. Phase atmosphere changes contrast, not the engine.
public enum Look {
    public static let field = Color.black
    public static let ink = Color.white
    public static let mute = Color.white.opacity(0.72)
    public static let dim = Color.white.opacity(0.42)
    public static let accent = Color.cyan
    public static let well = Color.white.opacity(0.08)

    public static let action = accent
    public static let time = accent
    public static let ringTrack = Color.white.opacity(0.14)
    public static let corner: CGFloat = 8
}
