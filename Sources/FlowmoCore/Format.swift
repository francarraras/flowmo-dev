import Foundation

public enum Format {
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
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
}
