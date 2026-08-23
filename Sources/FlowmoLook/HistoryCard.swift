import SwiftUI
import FlowmoCore

/// One finished session. Parked lines stay on the card.
public struct HistorySessionCard: View {
    @Environment(\.atmosphere) private var atmo
    var session: CompletedSession

    public init(session: CompletedSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(session.intention.isEmpty ? "No intention" : session.intention)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Format.clock(session.focusSeconds))
                    .font(.system(.body, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(atmo.mute)
            }
            Text(session.endedAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(atmo.faint)
            if !session.captures.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(session.captures.enumerated()), id: \.offset) { _, item in
                        Text(item.text)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(atmo.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            } else if session.captureCount > 0 {
                Text("\(session.captureCount) parked")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(atmo.mute)
                    .padding(.top, 4)
            }
            if let recall = session.recallText, !recall.isEmpty {
                Text(recall)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(atmo.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(atmo.well)
        .clipShape(RoundedRectangle(cornerRadius: Look.corner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
