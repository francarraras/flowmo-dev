import Foundation

public enum Format {
    /// Visible instead of crashing or presenting corrupt numeric state as time.
    public static let corruptionIndicator = "—"

    public static func clock(_ interval: TimeInterval) -> String {
        guard let seconds = safeRoundedSeconds(interval) else { return corruptionIndicator }
        return render(seconds)
    }

    /// Countdowns stay on 00:01 until the phase is actually over.
    public static func remainingClock(_ interval: TimeInterval) -> String {
        guard interval.isFinite,
            interval <= WorldPersistenceLimits.maximumAggregateSeconds
        else {
            return corruptionIndicator
        }
        return render(remainingSeconds(interval))
    }

    public static func remainingSeconds(_ interval: TimeInterval) -> Int {
        if interval.isNaN || interval == -.infinity { return 0 }
        if interval == .infinity || interval > WorldPersistenceLimits.maximumAggregateSeconds {
            return Int.max
        }
        let clamped = max(0, interval)
        if clamped == 0 { return 0 }
        return Int(ceil(clamped - 1e-9))
    }

    public static func minutes(_ interval: TimeInterval) -> String {
        guard interval.isFinite,
            interval <= WorldPersistenceLimits.maximumAggregateSeconds
        else {
            return corruptionIndicator
        }
        let safeInterval = max(0, interval)
        let minutes = safeInterval / 60
        if minutes >= 10 {
            return String(format: "%.0fm", minutes)
        }
        if minutes >= 1 {
            return String(format: "%.1fm", minutes)
        }
        return String(format: "%.0fs", safeInterval)
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
        func trim(_ value: Double) -> String {
            value.isFinite ? String(format: "%g", value) : corruptionIndicator
        }
        guard let phase = view.phase else {
            return """
                Flowmo  idle
                last \(view.lastIntention.isEmpty ? "—" : terminalText(view.lastIntention))
                today \(clock(view.todayFocusSeconds))
                ratio \(trim(view.ratio))
                """
        }
        let paused = view.isPaused ? "  paused" : ""
        switch phase {
        case .prime:
            return """
                Flowmo  prime\(paused)  \(terminalText(view.intention))
                \(remainingClock(view.remaining ?? 0)) remaining
                """
        case .focus:
            return """
                Flowmo  focus\(paused)  \(terminalText(view.intention))
                \(clock(view.elapsed))
                \(earned(view.earnedBreakSeconds))
                """
        case .onBreak:
            return """
                Flowmo  break\(paused)  \(terminalText(view.intention))
                \(remainingClock(view.remaining ?? 0)) remaining
                earned from \(minutes(view.focusSeconds)) focus
                """
        case .recall:
            return """
                Flowmo  reflection\(paused)  \(terminalText(view.intention))
                \(FlowmoCopy.reflectionPrompt)
                \(remainingClock(view.remaining ?? 0)) remaining
                """
        case .closeBeat:
            let recall = terminalText(view.recallText).trimmingCharacters(in: .whitespacesAndNewlines)
            var lines = [
                "Flowmo  close beat\(paused)",
                "focus \(clock(view.focusSeconds))",
                "break \(clock(view.breakSeconds ?? 0))",
            ]
            if !recall.isEmpty { lines.append(recall) }
            for item in view.captures {
                lines.append(terminalText(item.text))
            }
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

    private static func safeRoundedSeconds(_ interval: TimeInterval) -> Int? {
        guard interval.isFinite,
            interval <= WorldPersistenceLimits.maximumAggregateSeconds
        else {
            return nil
        }
        return Int(max(0, interval).rounded())
    }

    /// User text in the living terminal must remain one inert display line.
    /// Replace terminal controls with spaces while preserving ordinary Unicode.
    private static func terminalText(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Unicode.Scalar in
            let code = scalar.value
            let isC0 = code <= 0x1F
            let isDelete = code == 0x7F
            let isC1 = (0x80...0x9F).contains(code)
            let isLineSeparator = code == 0x2028 || code == 0x2029
            return (isC0 || isDelete || isC1 || isLineSeparator) ? " " : scalar
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

/// Focus count-up marks. A short grow fires the first time elapsed crosses each.
public enum ClockMarks {
    public static let minutes: [Int] = [5, 10, 15, 30, 45, 60]

    /// Highest mark in `(from, to]`. Nil if none, or if time went backwards.
    public static func crossing(from old: TimeInterval, to new: TimeInterval) -> Int? {
        guard new > old else { return nil }
        var hit: Int?
        for mark in minutes {
            let edge = TimeInterval(mark * 60)
            if old < edge, new >= edge {
                hit = mark
            }
        }
        return hit
    }
}
