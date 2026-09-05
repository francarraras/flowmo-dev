import SwiftUI

/// Intention plus the beat. Same slot every phase so the circle does not jump.
public struct PhaseLead: View {
    var line: String
    var cue: String
    var tone: Color

    public init(_ line: String, cue: String, tone: Color = Atmosphere.canvas.ink) {
        self.line = line
        self.cue = cue
        self.tone = tone
    }

    private var lineLimit: Int {
        #if os(iOS)
            3
        #else
            1
        #endif
    }

    public var body: some View {
        VStack(spacing: 4) {
            Text(line)
                .font(.system(.body, design: .default).weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.85)
                .foregroundStyle(tone)
            Text(cue)
                .font(.system(.caption).weight(.medium))
                .tracking(0.2)
                .foregroundStyle(Look.mute)
                .frame(minHeight: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Chrome icon: well + ink on hover. Lit stays ink when the control is on.
public struct ChromeGlyph: View {
    @Environment(\.atmosphere) private var atmo
    var systemName: String
    var lit: Bool
    var compact: Bool
    @State private var hovering = false

    public init(_ systemName: String, lit: Bool = false, compact: Bool = false) {
        self.systemName = systemName
        self.lit = lit
        self.compact = compact
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(compact ? .footnote : .body, design: .default).weight(.medium))
            .foregroundStyle((hovering || lit) ? atmo.ink : atmo.mute)
            .frame(width: compact ? 22 : 36, height: compact ? 22 : 28)
            .background {
                Circle()
                    .fill(atmo.ink.opacity(hovering ? 0.16 : 0))
                    .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
            }
            .contentShape(Rectangle())
            .animation(Motion.hover, value: hovering)
            .onHover { hovering = $0 }
    }
}
