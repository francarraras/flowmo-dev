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
