import ActivityKit
import FlowmoActivity
import SwiftUI
import WidgetKit

private enum FocusInk {
    static let field = Color(red: 9 / 255, green: 10 / 255, blue: 12 / 255)
    static let primary = Color(red: 243 / 255, green: 241 / 255, blue: 234 / 255)
}

private struct FocusMark: View {
    var body: some View {
        Image(systemName: "sun.horizon")
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(FocusInk.primary)
            .accessibilityHidden(true)
    }
}

private struct FocusClock: View {
    let startedAt: Date

    var body: some View {
        Text(startedAt, style: .timer)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .foregroundStyle(FocusInk.primary)
            .accessibilityLabel("Focus time")
            .accessibilityValue(Text(startedAt, style: .timer))
    }
}

private struct FocusLockScreen: View {
    let startedAt: Date

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Flowmo")
                    .font(.caption)
                    .foregroundStyle(FocusInk.primary.opacity(0.72))
                HStack(spacing: 8) {
                    FocusMark()
                    Text("Focus")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(FocusInk.primary)
                }
            }
            Spacer(minLength: 12)
            FocusClock(startedAt: startedAt)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .multilineTextAlignment(.trailing)
        }
        .padding(18)
        .activityBackgroundTint(FocusInk.field)
        .activitySystemActionForegroundColor(FocusInk.primary)
    }
}

@main
struct FlowmoFocusActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLockScreen(startedAt: context.state.startedAt)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        FocusMark()
                        Text("Focus")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(FocusInk.primary)
                    }
                    .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusClock(startedAt: context.state.startedAt)
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .multilineTextAlignment(.trailing)
                        .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Open Flowmo")
                        .font(.caption)
                        .foregroundStyle(FocusInk.primary.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            } compactLeading: {
                FocusMark()
                    .padding(.leading, 3)
            } compactTrailing: {
                FocusClock(startedAt: context.state.startedAt)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
            } minimal: {
                FocusMark()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Focus is running")
            }
            .keylineTint(FocusInk.primary)
        }
    }
}
