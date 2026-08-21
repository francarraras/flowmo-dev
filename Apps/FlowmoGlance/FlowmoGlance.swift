import SwiftUI
import WidgetKit
import FlowmoCore

private struct GlanceEntry: TimelineEntry {
    let date: Date
    let text: String
    let isPaused: Bool

    var accessibilityText: String {
        guard isPaused else { return text }
        let clock = text.hasPrefix("· ") ? String(text.dropFirst(2)) : text
        return "Paused, \(clock)"
    }
}

private struct Provider: TimelineProvider {
    private static let focusCadence: TimeInterval = 15 * 60
    private static let maximumTimelineEntries = 12

    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), text: "Flowmo", isPaused: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        let now = Date()
        completion(entry(world: loadWorld(), at: now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        let world = loadWorld()
        let dates = timelineDates(world: world, now: now)
        let entries = dates.map { date in
            entry(world: world, at: date)
        }
        let policy: TimelineReloadPolicy = dates.count == 1 ? .never : .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }

    private func timelineDates(world: World, now: Date) -> [Date] {
        var dates = [now]
        var projected = Engine(world: world)
        projected.sync(now: now)

        guard let live = projected.world.live, !live.isPaused, live.phase != .closeBeat else {
            return dates
        }

        var nextCoarse = now.addingTimeInterval(Self.focusCadence)
        while dates.count < Self.maximumTimelineEntries {
            guard let projectedLive = projected.world.live,
                  !projectedLive.isPaused,
                  projectedLive.phase != .closeBeat else {
                break
            }

            let previous = dates[dates.count - 1]
            let next: Date
            if let boundary = timedBoundary(in: projectedLive),
               boundary > previous,
               boundary <= nextCoarse {
                next = boundary
                if boundary >= nextCoarse {
                    nextCoarse = nextCoarse.addingTimeInterval(Self.focusCadence)
                }
            } else {
                next = nextCoarse
                nextCoarse = nextCoarse.addingTimeInterval(Self.focusCadence)
            }

            dates.append(next)
            projected.sync(now: next)
        }
        return dates
    }

    private func timedBoundary(in live: SessionSnapshot) -> Date? {
        switch live.phase {
        case .prime:
            return live.phaseStartedAt.addingTimeInterval(live.primeDuration)
        case .onBreak:
            guard let startedAt = live.breakStartedAt, let duration = live.breakDuration else {
                return nil
            }
            return startedAt.addingTimeInterval(duration)
        case .recall:
            return live.phaseStartedAt.addingTimeInterval(live.recallDuration)
        case .focus, .closeBeat:
            return nil
        }
    }

    /// Project from the shared snapshot. The widget never syncs or writes the store.
    private func entry(world: World, at date: Date) -> GlanceEntry {
        var engine = Engine(world: world)
        engine.sync(now: date)
        let status = engine.status(now: date)
        return GlanceEntry(
            date: date,
            text: Format.glance(status),
            isPaused: status.isPaused
        )
    }

    private func loadWorld() -> World {
        guard let root = Store.phoneSharedRoot() else { return .empty }
        return (try? Store(root: root).load()) ?? .empty
    }
}

private struct GlanceView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GlanceEntry

    private var clockSize: CGFloat {
        family == .systemMedium ? 44 : 34
    }

    var body: some View {
        Text(entry.text)
            .font(.system(size: clockSize, weight: .light, design: .default))
            .monospacedDigit()
            .tracking(-0.8)
            .foregroundStyle(Color.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text(verbatim: entry.accessibilityText))
            .flowmoContainerBackground()
    }
}

private extension View {
    @ViewBuilder
    func flowmoContainerBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) {
                Color.black
            }
        } else {
            background(Color.black)
        }
    }
}

@main
struct FlowmoGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceKind.id, provider: Provider()) { entry in
            GlanceView(entry: entry)
        }
        .configurationDisplayName("Flowmo")
        .description("Session clock.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
