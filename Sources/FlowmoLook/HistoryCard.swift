import FlowmoCore
import SwiftUI

/// One finished session. Collapsed is a scan row. Tap opens that session only.
public struct HistorySessionCard: View {
    @Environment(\.atmosphere) private var atmo
    var session: CompletedSession
    var expanded: Bool
    var onToggle: () -> Void

    public init(session: CompletedSession, expanded: Bool, onToggle: @escaping () -> Void) {
        self.session = session
        self.expanded = expanded
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 8 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.intention.isEmpty ? "No intention" : session.intention)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .lineLimit(expanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: expanded)
                Spacer(minLength: 8)
                if !expanded {
                    Text(Format.clock(session.focusSeconds))
                        .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
                        .foregroundStyle(atmo.mute)
                }
            }
            Text(session.endedAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(atmo.mute)

            if expanded {
                clocks
                if parkedCount > 0 {
                    labeled("Parked") {
                        if session.captures.isEmpty {
                            Text("\(parkedCount) parked")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(atmo.mute)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(session.captures.enumerated()), id: \.offset) { _, item in
                                    Text(item.text)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(atmo.mute)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if let recall = session.recallText, !recall.isEmpty {
                    labeled("Reflection") {
                        Text(recall)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(atmo.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if hasWriting {
                Text(collapsedMark)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(atmo.mute)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(atmo.well)
        .clipShape(RoundedRectangle(cornerRadius: Look.corner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Look.corner, style: .continuous))
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: expanded ? .contain : .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Shows less" : "Shows parked lines and reflection")
    }

    private var parkedCount: Int {
        session.captures.isEmpty ? session.captureCount : session.captures.count
    }

    private var hasWriting: Bool {
        parkedCount > 0 || !(session.recallText?.isEmpty ?? true)
    }

    private var collapsedMark: String {
        var parts: [String] = []
        if parkedCount > 0 {
            parts.append("\(parkedCount) parked")
        }
        if let recall = session.recallText, !recall.isEmpty {
            parts.append("reflection")
        }
        return parts.joined(separator: " · ")
    }

    private var clocks: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            namedClock("Focused", seconds: session.focusSeconds, tone: atmo.ink)
            namedClock("Rested", seconds: session.breakSeconds, tone: Atmosphere.rest)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func namedClock(_ name: String, seconds: TimeInterval, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(atmo.mute)
            Text(Format.clock(seconds))
                .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(tone)
        }
    }

    private func labeled<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(atmo.mute)
            content()
        }
        .padding(.top, 2)
    }
}
