import FlowmoCore
import SwiftUI

/// One finished session. Its disclosure and optional resumption are distinct actions.
public struct HistorySessionCard: View {
    @Environment(\.atmosphere) private var atmo
    var session: CompletedSession
    var expanded: Bool
    var resumptionTitle: String?
    var onResume: (() -> Void)?
    var onToggle: () -> Void

    public init(
        session: CompletedSession,
        expanded: Bool,
        resumptionTitle: String? = nil,
        onResume: (() -> Void)? = nil,
        onToggle: @escaping () -> Void
    ) {
        self.session = session
        self.expanded = expanded
        self.resumptionTitle = resumptionTitle
        self.onResume = onResume
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 8 : 4) {
            disclosure

            if expanded {
                clocks
                if parkedCount > 0 {
                    labeled("Parked") {
                        if session.captures.isEmpty {
                            Text("\(parkedCount) parked")
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(atmo.mute)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(session.captures.enumerated()), id: \.offset) { _, item in
                                    Text(item.text)
                                        .font(.system(.caption, design: .default))
                                        .foregroundStyle(atmo.mute)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if let recall = session.recallText, !recall.isEmpty {
                    labeled("Next step") {
                        Text(recall)
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(atmo.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let visibleResumptionTitle, let onResume {
                    QuietButton(visibleResumptionTitle, action: onResume)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(atmo.well)
        .clipShape(RoundedRectangle(cornerRadius: Look.corner, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var disclosure: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: expanded ? 8 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.intention.isEmpty ? "No intention" : session.intention)
                        .font(.system(.body, design: .default).weight(.medium))
                        .lineLimit(expanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: expanded)
                    Spacer(minLength: 8)
                    if !expanded {
                        Text(Format.clock(session.focusSeconds))
                            .font(.system(.body, design: .default).weight(.medium).monospacedDigit())
                            .foregroundStyle(atmo.mute)
                    }
                }
                Text(session.endedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(atmo.mute)

                if !expanded, hasWriting {
                    Text(collapsedMark)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(atmo.mute)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(expanded ? "Shows less" : "Shows parked lines and next step")
    }

    private var parkedCount: Int {
        session.captures.isEmpty ? session.captureCount : session.captures.count
    }

    private var hasWriting: Bool {
        parkedCount > 0 || !(session.recallText?.isEmpty ?? true)
    }

    private var visibleResumptionTitle: String? {
        guard let resumptionTitle else { return nil }
        let trimmed = resumptionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var collapsedMark: String {
        var parts: [String] = []
        if parkedCount > 0 {
            parts.append("\(parkedCount) parked")
        }
        if let recall = session.recallText, !recall.isEmpty {
            parts.append("Next step")
        }
        return parts.joined(separator: " · ")
    }

    private var clocks: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            namedClock("Focused", seconds: session.focusSeconds, tone: atmo.ink)
            namedClock("Break earned", seconds: session.breakSeconds, tone: Atmosphere.rest)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func namedClock(_ name: String, seconds: TimeInterval, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: 11, weight: .medium, design: .default))
                .tracking(0.6)
                .foregroundStyle(atmo.mute)
            Text(Format.clock(seconds))
                .font(.system(.body, design: .default).weight(.medium).monospacedDigit())
                .foregroundStyle(tone)
        }
    }

    private func labeled<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.system(size: 11, weight: .medium, design: .default))
                .tracking(0.6)
                .foregroundStyle(atmo.mute)
            content()
        }
        .padding(.top, 2)
    }
}
