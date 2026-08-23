import Foundation

/// Generous persistence limits that keep a corrupt local file from becoming an
/// unbounded allocation or an unsafe numeric input. They are intentionally far
/// above the product's normal two-minute/three-minute/session-sized values.
public enum WorldPersistenceLimits {
    public static let maximumFileBytes: Int64 = 4 * 1024 * 1024
    public static let maximumSessionSeconds: TimeInterval = 366 * 24 * 60 * 60
    public static let maximumPhaseSeconds: TimeInterval = 24 * 60 * 60
    public static let maximumHistoryCount = 10_000
    public static let maximumRecentFocusCount = 100
    public static let maximumCapturesPerSession = 1_000
    public static let maximumGuardIdentifierCount = 256
    public static let maximumCounter = 10_000_000
    public static let maximumIntentionBytes = 16 * 1024
    public static let maximumCaptureTextBytes = 64 * 1024
    public static let maximumRecallTextBytes = 256 * 1024
    public static let maximumNoteBytes = 64 * 1024
    public static let maximumGuardIdentifierBytes = 1_024
    public static let maximumAggregateTextBytes = 2 * 1024 * 1024

    static let maximumAggregateSeconds = maximumSessionSeconds * TimeInterval(maximumHistoryCount)
    static let maximumJSONNodes = 100_000
    static let maximumJSONDepth = 32
    static let maximumDateSecondsSince1970: TimeInterval = 7_258_118_400  // 2200-01-01 UTC
}

public struct WorldValidationError: LocalizedError, Equatable, Sendable {
    public let path: String
    public let problem: String

    public init(path: String, problem: String) {
        self.path = path
        self.problem = problem
    }

    public var errorDescription: String? {
        "Invalid Flowmo data at \(path): \(problem)."
    }
}

extension World {
    /// Validate a fully decoded world before it reaches clocks, aggregates, or
    /// persistence. Values are rejected, never truncated or reinterpreted.
    public func validateForPersistence() throws {
        var aggregateTextBytes = 0

        func text(_ value: String, path: String, maximum: Int) throws {
            let count = value.utf8.count
            guard count <= maximum else {
                throw WorldValidationError(path: path, problem: "text is \(count) UTF-8 bytes; maximum is \(maximum)")
            }
            let (sum, overflow) = aggregateTextBytes.addingReportingOverflow(count)
            guard !overflow, sum <= WorldPersistenceLimits.maximumAggregateTextBytes else {
                throw WorldValidationError(
                    path: "$",
                    problem: "aggregate text exceeds \(WorldPersistenceLimits.maximumAggregateTextBytes) UTF-8 bytes"
                )
            }
            aggregateTextBytes = sum
        }

        func finiteRange(_ value: Double, path: String, range: ClosedRange<Double>) throws {
            guard value.isFinite else {
                throw WorldValidationError(path: path, problem: "number must be finite")
            }
            guard range.contains(value) else {
                throw WorldValidationError(
                    path: path, problem: "number \(value) is outside \(range.lowerBound)...\(range.upperBound)")
            }
        }

        func date(_ value: Date, path: String) throws {
            let seconds = value.timeIntervalSince1970
            guard seconds.isFinite else {
                throw WorldValidationError(path: path, problem: "date must be finite")
            }
            // This bounds Date arithmetic while retaining centuries of valid local history.
            guard 0...WorldPersistenceLimits.maximumDateSecondsSince1970 ~= seconds else {
                throw WorldValidationError(path: path, problem: "date is outside 1970...2199")
            }
        }

        func elapsed(from start: Date, to end: Date, path: String) throws {
            let seconds = end.timeIntervalSince(start)
            guard seconds.isFinite, 0...WorldPersistenceLimits.maximumSessionSeconds ~= seconds else {
                throw WorldValidationError(
                    path: path,
                    problem: "timestamp span must be within 0...\(WorldPersistenceLimits.maximumSessionSeconds) seconds"
                )
            }
        }

        func capture(_ item: CaptureItem, path: String) throws {
            try text(item.text, path: "\(path).text", maximum: WorldPersistenceLimits.maximumCaptureTextBytes)
            try date(item.createdAt, path: "\(path).createdAt")
        }

        try finiteRange(
            config.primeSeconds,
            path: "$.config.primeSeconds",
            range: 0...WorldPersistenceLimits.maximumPhaseSeconds
        )
        try finiteRange(
            config.recallSeconds,
            path: "$.config.recallSeconds",
            range: 0...WorldPersistenceLimits.maximumPhaseSeconds
        )
        try finiteRange(config.defaultBreakRatio, path: "$.config.defaultBreakRatio", range: 3...8)

        let guardIDs = config.focusGuard.bundleIdentifiers
        guard guardIDs.count <= WorldPersistenceLimits.maximumGuardIdentifierCount else {
            throw WorldValidationError(
                path: "$.config.focusGuard.bundleIdentifiers",
                problem:
                    "array has \(guardIDs.count) items; maximum is \(WorldPersistenceLimits.maximumGuardIdentifierCount)"
            )
        }
        for (index, identifier) in guardIDs.enumerated() {
            try text(
                identifier,
                path: "$.config.focusGuard.bundleIdentifiers[\(index)]",
                maximum: WorldPersistenceLimits.maximumGuardIdentifierBytes
            )
        }

        try finiteRange(profile.breakRatio, path: "$.profile.breakRatio", range: 3...8)
        guard (0...WorldPersistenceLimits.maximumCounter).contains(profile.sessionCount) else {
            throw WorldValidationError(
                path: "$.profile.sessionCount",
                problem: "counter \(profile.sessionCount) is outside 0...\(WorldPersistenceLimits.maximumCounter)"
            )
        }
        try finiteRange(
            profile.totalFocusSeconds,
            path: "$.profile.totalFocusSeconds",
            range: 0...WorldPersistenceLimits.maximumAggregateSeconds
        )
        guard profile.recentFocusSeconds.count <= WorldPersistenceLimits.maximumRecentFocusCount else {
            throw WorldValidationError(
                path: "$.profile.recentFocusSeconds",
                problem:
                    "array has \(profile.recentFocusSeconds.count) items; maximum is \(WorldPersistenceLimits.maximumRecentFocusCount)"
            )
        }
        for (index, seconds) in profile.recentFocusSeconds.enumerated() {
            try finiteRange(
                seconds,
                path: "$.profile.recentFocusSeconds[\(index)]",
                range: 0...WorldPersistenceLimits.maximumSessionSeconds
            )
        }
        if let note = profile.lastNote {
            try text(note, path: "$.profile.lastNote", maximum: WorldPersistenceLimits.maximumNoteBytes)
        }
        try text(
            profile.lastIntention,
            path: "$.profile.lastIntention",
            maximum: WorldPersistenceLimits.maximumIntentionBytes
        )

        if let live {
            try text(live.intention, path: "$.live.intention", maximum: WorldPersistenceLimits.maximumIntentionBytes)
            try finiteRange(live.breakRatio, path: "$.live.breakRatio", range: 3...8)
            try date(live.startedAt, path: "$.live.startedAt")
            try date(live.phaseStartedAt, path: "$.live.phaseStartedAt")
            try elapsed(from: live.startedAt, to: live.phaseStartedAt, path: "$.live.phaseStartedAt")
            if let value = live.lastResumedAt {
                try date(value, path: "$.live.lastResumedAt")
                try elapsed(from: live.startedAt, to: value, path: "$.live.lastResumedAt")
            }
            if let value = live.focusStartedAt {
                try date(value, path: "$.live.focusStartedAt")
                try elapsed(from: live.startedAt, to: value, path: "$.live.focusStartedAt")
            }
            if let value = live.focusEndedAt {
                try date(value, path: "$.live.focusEndedAt")
            }
            if let start = live.focusStartedAt, let end = live.focusEndedAt {
                try elapsed(from: start, to: end, path: "$.live.focusEndedAt")
            }
            if let value = live.breakStartedAt {
                try date(value, path: "$.live.breakStartedAt")
                try elapsed(from: live.startedAt, to: value, path: "$.live.breakStartedAt")
            }
            if let value = live.breakDuration {
                try finiteRange(
                    value,
                    path: "$.live.breakDuration",
                    range: 0...WorldPersistenceLimits.maximumSessionSeconds
                )
            }
            try finiteRange(
                live.primeDuration,
                path: "$.live.primeDuration",
                range: 0...WorldPersistenceLimits.maximumPhaseSeconds
            )
            try finiteRange(
                live.recallDuration,
                path: "$.live.recallDuration",
                range: 0...WorldPersistenceLimits.maximumPhaseSeconds
            )
            try text(live.recallText, path: "$.live.recallText", maximum: WorldPersistenceLimits.maximumRecallTextBytes)
            if let value = live.pausedAt {
                try date(value, path: "$.live.pausedAt")
                try elapsed(from: live.startedAt, to: value, path: "$.live.pausedAt")
            }
            if let value = live.frozenElapsed {
                try finiteRange(
                    value,
                    path: "$.live.frozenElapsed",
                    range: 0...WorldPersistenceLimits.maximumSessionSeconds
                )
            }
            if let value = live.frozenRemaining {
                try finiteRange(
                    value,
                    path: "$.live.frozenRemaining",
                    range: 0...WorldPersistenceLimits.maximumSessionSeconds
                )
            }
            guard live.captures.count <= WorldPersistenceLimits.maximumCapturesPerSession else {
                throw WorldValidationError(
                    path: "$.live.captures",
                    problem:
                        "array has \(live.captures.count) items; maximum is \(WorldPersistenceLimits.maximumCapturesPerSession)"
                )
            }
            for (index, item) in live.captures.enumerated() {
                try capture(item, path: "$.live.captures[\(index)]")
            }
        }

        guard history.count <= WorldPersistenceLimits.maximumHistoryCount else {
            throw WorldValidationError(
                path: "$.history",
                problem: "array has \(history.count) items; maximum is \(WorldPersistenceLimits.maximumHistoryCount)"
            )
        }
        for (index, session) in history.enumerated() {
            let path = "$.history[\(index)]"
            try text(
                session.intention, path: "\(path).intention", maximum: WorldPersistenceLimits.maximumIntentionBytes)
            try finiteRange(
                session.focusSeconds,
                path: "\(path).focusSeconds",
                range: 0...WorldPersistenceLimits.maximumSessionSeconds
            )
            try finiteRange(
                session.breakSeconds,
                path: "\(path).breakSeconds",
                range: 0...WorldPersistenceLimits.maximumSessionSeconds
            )
            guard (0...WorldPersistenceLimits.maximumCounter).contains(session.captureCount) else {
                throw WorldValidationError(
                    path: "\(path).captureCount",
                    problem: "counter \(session.captureCount) is outside 0...\(WorldPersistenceLimits.maximumCounter)"
                )
            }
            guard session.captures.count <= WorldPersistenceLimits.maximumCapturesPerSession else {
                throw WorldValidationError(
                    path: "\(path).captures",
                    problem:
                        "array has \(session.captures.count) items; maximum is \(WorldPersistenceLimits.maximumCapturesPerSession)"
                )
            }
            for (captureIndex, item) in session.captures.enumerated() {
                try capture(item, path: "\(path).captures[\(captureIndex)]")
            }
            if let recall = session.recallText {
                try text(recall, path: "\(path).recallText", maximum: WorldPersistenceLimits.maximumRecallTextBytes)
            }
            try date(session.endedAt, path: "\(path).endedAt")
        }
    }
}

enum RawWorldValidation {
    /// Codable migrations intentionally normalize Focus Guard identifiers. Check
    /// raw collection/text quotas first so normalization cannot hide an oversized
    /// attacker-controlled representation from decoded-world validation.
    static func validate(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WorldValidationError(path: "$", problem: "JSON could not be parsed (\(error.localizedDescription))")
        }
        var nodes = 0
        var textBytes = 0
        try walk(object, path: "$", depth: 0, nodes: &nodes, textBytes: &textBytes)

        guard
            let root = object as? [String: Any],
            let config = root["config"] as? [String: Any],
            let focusGuard = config["focusGuard"] as? [String: Any],
            let identifiers = focusGuard["bundleIdentifiers"] as? [Any]
        else { return }

        guard identifiers.count <= WorldPersistenceLimits.maximumGuardIdentifierCount else {
            throw WorldValidationError(
                path: "$.config.focusGuard.bundleIdentifiers",
                problem:
                    "raw array has \(identifiers.count) items; maximum is \(WorldPersistenceLimits.maximumGuardIdentifierCount)"
            )
        }
        for (index, value) in identifiers.enumerated() {
            guard let identifier = value as? String else { continue }
            let count = identifier.utf8.count
            guard count <= WorldPersistenceLimits.maximumGuardIdentifierBytes else {
                throw WorldValidationError(
                    path: "$.config.focusGuard.bundleIdentifiers[\(index)]",
                    problem:
                        "raw text is \(count) UTF-8 bytes; maximum is \(WorldPersistenceLimits.maximumGuardIdentifierBytes)"
                )
            }
        }
    }

    private static func walk(
        _ value: Any,
        path: String,
        depth: Int,
        nodes: inout Int,
        textBytes: inout Int
    ) throws {
        guard depth <= WorldPersistenceLimits.maximumJSONDepth else {
            throw WorldValidationError(
                path: path, problem: "JSON nesting exceeds \(WorldPersistenceLimits.maximumJSONDepth) levels")
        }
        nodes += 1
        guard nodes <= WorldPersistenceLimits.maximumJSONNodes else {
            throw WorldValidationError(
                path: path, problem: "JSON contains more than \(WorldPersistenceLimits.maximumJSONNodes) values")
        }

        if let string = value as? String {
            let (sum, overflow) = textBytes.addingReportingOverflow(string.utf8.count)
            guard !overflow, sum <= WorldPersistenceLimits.maximumAggregateTextBytes else {
                throw WorldValidationError(
                    path: "$",
                    problem:
                        "raw aggregate text exceeds \(WorldPersistenceLimits.maximumAggregateTextBytes) UTF-8 bytes"
                )
            }
            textBytes = sum
        } else if let array = value as? [Any] {
            guard array.count <= WorldPersistenceLimits.maximumHistoryCount else {
                throw WorldValidationError(
                    path: path,
                    problem:
                        "raw array has \(array.count) items; maximum is \(WorldPersistenceLimits.maximumHistoryCount)"
                )
            }
            for (index, item) in array.enumerated() {
                try walk(item, path: "\(path)[\(index)]", depth: depth + 1, nodes: &nodes, textBytes: &textBytes)
            }
        } else if let dictionary = value as? [String: Any] {
            for (key, item) in dictionary {
                try walk(item, path: "\(path).\(key)", depth: depth + 1, nodes: &nodes, textBytes: &textBytes)
            }
        }
    }
}
