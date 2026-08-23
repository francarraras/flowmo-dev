import FlowmoCore
import FlowmoLook
import SwiftUI
import WidgetKit

private enum GlanceContent {
    case text(String, accessibility: String?)
    case elapsed(since: Date)
    case countdown(ClosedRange<Date>)
}

private enum GlanceStoreSnapshot {
    case available(World)
    case unavailable
}

private struct GlanceEntry: TimelineEntry {
    let date: Date
    let content: GlanceContent
    let phase: SessionPhase?
    let isPaused: Bool
}

private struct Provider: TimelineProvider {
    private static let maximumTimelineEntries = 4

    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), content: .text("Flowmo", accessibility: nil), phase: nil, isPaused: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        let now = Date()
        completion(entry(snapshot: loadWorld(), at: now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        let snapshot = loadWorld()
        guard case .available(let world) = snapshot else {
            completion(
                Timeline(entries: [entry(snapshot: snapshot, at: now)], policy: .after(now.addingTimeInterval(15 * 60)))
            )
            return
        }
        let entries = timelineDates(world: world, now: now).map { date in
            entry(snapshot: snapshot, at: date)
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
                boundary > dates[dates.count - 1]
            else {
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
    private func entry(snapshot: GlanceStoreSnapshot, at date: Date) -> GlanceEntry {
        guard case .available(let world) = snapshot else {
            return GlanceEntry(
                date: date,
                content: .text("Unavailable", accessibility: "Flowmo data unavailable"),
                phase: nil,
                isPaused: false
            )
        }
        return entry(world: world, at: date)
    }

    private func entry(world: World, at date: Date) -> GlanceEntry {
        var engine = Engine(world: world)
        engine.sync(now: date)
        let status = engine.status(now: date)
        let phase = status.phase

        guard let live = engine.world.live else {
            return GlanceEntry(
                date: date,
                content: .text("Flowmo", accessibility: nil),
                phase: nil,
                isPaused: false
            )
        }
        if status.isPaused {
            let text = Format.glance(status)
            let clock = text.hasPrefix("· ") ? String(text.dropFirst(2)) : text
            return GlanceEntry(
                date: date,
                content: .text(text, accessibility: "Paused, \(clock)"),
                phase: phase,
                isPaused: true
            )
        }

        switch live.phase {
        case .prime:
            return countdownEntry(
                date: date,
                start: live.phaseStartedAt,
                duration: live.primeDuration,
                phase: .prime
            )
        case .focus:
            return GlanceEntry(
                date: date,
                content: .elapsed(since: live.focusStartedAt ?? live.phaseStartedAt),
                phase: .focus,
                isPaused: false
            )
        case .onBreak:
            guard let start = live.breakStartedAt, let duration = live.breakDuration else {
                return GlanceEntry(
                    date: date,
                    content: .text(Format.glance(status), accessibility: nil),
                    phase: .onBreak,
                    isPaused: false
                )
            }
            return countdownEntry(date: date, start: start, duration: duration, phase: .onBreak)
        case .recall:
            return countdownEntry(
                date: date,
                start: live.phaseStartedAt,
                duration: live.recallDuration,
                phase: .recall
            )
        case .closeBeat:
            return GlanceEntry(
                date: date,
                content: .text(Format.glance(status), accessibility: nil),
                phase: .closeBeat,
                isPaused: false
            )
        }
    }

    private func countdownEntry(
        date: Date,
        start: Date,
        duration: TimeInterval,
        phase: SessionPhase
    ) -> GlanceEntry {
        let end = start.addingTimeInterval(max(0, duration))
        return GlanceEntry(
            date: date,
            content: .countdown(start...max(start, end)),
            phase: phase,
            isPaused: false
        )
    }

    private func loadWorld() -> GlanceStoreSnapshot {
        guard let root = Store.phoneSharedRoot() else {
            FlowmoDiagnosticLog.emit(.storeUnavailable, operation: .appGroup)
            return .unavailable
        }
        do {
            return .available(try Store(root: root).load())
        } catch {
            FlowmoDiagnosticLog.emit(.storeUnreadable, operation: .load)
            return .unavailable
        }
    }
}

private struct GlanceView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GlanceEntry

    private var clockSize: CGFloat {
        family == .systemMedium ? 44 : 34
    }

    private var atmo: Atmosphere {
        Atmosphere.canvas
    }

    var body: some View {
        clock
            .font(.system(size: clockSize, weight: .medium, design: .rounded))
            .monospacedDigit()
            .tracking(-0.8)
            .foregroundStyle(entry.isPaused ? atmo.faint : (entry.phase == nil ? atmo.mute : atmo.ink))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .flowmoContainerBackground(atmo.field)
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

extension View {
    @ViewBuilder
    fileprivate func flowmoContainerBackground(_ field: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) {
                field
            }
        } else {
            background(field)
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
