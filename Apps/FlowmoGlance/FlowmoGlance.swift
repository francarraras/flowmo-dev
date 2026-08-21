import SwiftUI
import WidgetKit
import FlowmoCore

private enum GlanceContent {
    case text(String, accessibility: String?)
    case elapsed(since: Date)
    case countdown(ClosedRange<Date>)
}

private struct GlanceEntry: TimelineEntry {
    let date: Date
    let content: GlanceContent
}

private struct Provider: TimelineProvider {
    private static let maximumTimelineEntries = 4

    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), content: .text("Flowmo", accessibility: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        let now = Date()
        completion(entry(world: loadWorld(), at: now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        let world = loadWorld()
        let entries = timelineDates(world: world, now: now).map { date in
            entry(world: world, at: date)
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func timelineDates(world: World, now: Date) -> [Date] {
        var dates = [now]
        var projected = Engine(world: world)
        projected.sync(now: now)

        while dates.count < Self.maximumTimelineEntries {
            guard let live = projected.world.live,
                  !live.isPaused,
                  live.phase != .closeBeat,
                  let boundary = timedBoundary(in: live),
                  boundary > dates[dates.count - 1] else {
                break
            }
            dates.append(boundary)
            projected.sync(now: boundary)
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

    /// Project from the shared snapshot. The widget never writes the store.
    private func entry(world: World, at date: Date) -> GlanceEntry {
        var engine = Engine(world: world)
        engine.sync(now: date)
        let status = engine.status(now: date)

        guard let live = engine.world.live else {
            return GlanceEntry(date: date, content: .text("Flowmo", accessibility: nil))
        }
        if status.isPaused {
            let text = Format.glance(status)
            let clock = text.hasPrefix("· ") ? String(text.dropFirst(2)) : text
            return GlanceEntry(
                date: date,
                content: .text(text, accessibility: "Paused, \(clock)")
            )
        }

        switch live.phase {
        case .prime:
            return countdownEntry(
                date: date,
                start: live.phaseStartedAt,
                duration: live.primeDuration
            )
        case .focus:
            return GlanceEntry(
                date: date,
                content: .elapsed(since: live.focusStartedAt ?? live.phaseStartedAt)
            )
        case .onBreak:
            guard let start = live.breakStartedAt, let duration = live.breakDuration else {
                return GlanceEntry(
                    date: date,
                    content: .text(Format.glance(status), accessibility: nil)
                )
            }
            return countdownEntry(date: date, start: start, duration: duration)
        case .recall:
            return countdownEntry(
                date: date,
                start: live.phaseStartedAt,
                duration: live.recallDuration
            )
        case .closeBeat:
            return GlanceEntry(
                date: date,
                content: .text(Format.glance(status), accessibility: nil)
            )
        }
    }

    private func countdownEntry(date: Date, start: Date, duration: TimeInterval) -> GlanceEntry {
        let end = start.addingTimeInterval(max(0, duration))
        return GlanceEntry(date: date, content: .countdown(start...max(start, end)))
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
        clock
            .font(.system(size: clockSize, weight: .light, design: .default))
            .monospacedDigit()
            .tracking(-0.8)
            .foregroundStyle(Color.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .flowmoContainerBackground()
    }

    @ViewBuilder
    private var clock: some View {
        switch entry.content {
        case .text(let text, let accessibility):
            Text(text)
                .accessibilityLabel(Text(verbatim: accessibility ?? text))
        case .elapsed(let start):
            Text(start, style: .timer)
        case .countdown(let interval):
            Text(timerInterval: interval, countsDown: true, showsHours: true)
        }
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
