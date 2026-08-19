import Foundation

public enum Format {
    public static func clock(_ interval: TimeInterval) -> String {
        render(max(0, Int(interval.rounded())))
    }

    /// Countdowns stay on 00:01 until the phase is actually over.
    public static func remainingClock(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        if clamped == 0 { return render(0) }
        return render(Int(ceil(clamped - 1e-9)))
    }

    public static func minutes(_ interval: TimeInterval) -> String {
        let minutes = interval / 60
        if minutes >= 10 {
            return String(format: "%.0fm", minutes)
        }
        if minutes >= 1 {
            return String(format: "%.1fm", minutes)
        }
        return String(format: "%.0fs", interval)
    }

    public static func earned(_ interval: TimeInterval) -> String {
        "\(minutes(interval)) earned"
    }

    /// Compact menu-bar title. Same clocks as the window.
    public static func glance(_ status: SessionStatus) -> String {
        let mark = status.isPaused ? "· " : ""
        guard let phase = status.phase else { return "Flowmo" }
        switch phase {
        case .prime, .onBreak, .recall:
            return mark + remainingClock(status.remaining ?? 0)
        case .focus:
            return mark + clock(status.elapsed)
        case .closeBeat:
            return mark + clock(status.focusSeconds)
        }
    }

    /// Living terminal frame. Same session facts as status, not a command list.
    public static func liveView(_ view: SessionStatus) -> String {
        func trim(_ value: Double) -> String { String(format: "%g", value) }
        guard let phase = view.phase else {
            return """
            Flowmo  idle
            last \(view.lastIntention.isEmpty ? "—" : view.lastIntention)
            today \(clock(view.todayFocusSeconds))
            ratio \(trim(view.ratio))
            """
        }
        let paused = view.isPaused ? "  paused" : ""
        switch phase {
        case .prime:
            return """
            Flowmo  prime\(paused)  \(view.intention)
            \(remainingClock(view.remaining ?? 0)) remaining
            """
        case .focus:
            return """
            Flowmo  focus\(paused)  \(view.intention)
            \(clock(view.elapsed))
            \(earned(view.earnedBreakSeconds))
            """
        case .onBreak:
            return """
            Flowmo  break\(paused)  \(view.intention)
            \(remainingClock(view.remaining ?? 0)) remaining
            earned from \(minutes(view.focusSeconds)) focus
            """
        case .recall:
            return """
            Flowmo  recall\(paused)  \(view.intention)
            What did you just do?
            \(remainingClock(view.remaining ?? 0)) remaining
            """
        case .closeBeat:
            let recall = view.recallText.trimmingCharacters(in: .whitespacesAndNewlines)
            var lines = [
                "Flowmo  close beat\(paused)",
                "focus \(clock(view.focusSeconds))",
                "break \(clock(view.breakSeconds ?? 0))",
            ]
            if !recall.isEmpty { lines.append(recall) }
            return lines.joined(separator: "\n")
        }
    }

    private static func render(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
