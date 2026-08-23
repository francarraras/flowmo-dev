import Foundation

public struct Config: Equatable, Sendable {
    public var primeSeconds: TimeInterval
    public var recallSeconds: TimeInterval
    public var defaultBreakRatio: Double
    public var focusGuard: FocusGuardConfiguration
    /// Phase-change sound. On by default.
    public var cuesEnabled: Bool

    public static let `default` = Config(
        primeSeconds: 2 * 60,
        recallSeconds: 3 * 60,
        defaultBreakRatio: 5,
        focusGuard: .default,
        cuesEnabled: true
    )

    /// 5:00 was the old default. Reflection is three minutes.
    public static func migratedRecall(_ stored: TimeInterval) -> TimeInterval {
        stored == 5 * 60 ? 3 * 60 : stored
    }

    public init(
        primeSeconds: TimeInterval,
        recallSeconds: TimeInterval,
        defaultBreakRatio: Double,
        focusGuard: FocusGuardConfiguration = .default,
        cuesEnabled: Bool = true
    ) {
        self.primeSeconds = primeSeconds
        self.recallSeconds = recallSeconds
        self.defaultBreakRatio = defaultBreakRatio
        self.focusGuard = focusGuard
        self.cuesEnabled = cuesEnabled
    }
}

extension Config: Codable {
    enum CodingKeys: String, CodingKey {
        case primeSeconds, recallSeconds, defaultBreakRatio, focusGuard, cuesEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primeSeconds = try c.decode(TimeInterval.self, forKey: .primeSeconds)
        recallSeconds = Config.migratedRecall(try c.decode(TimeInterval.self, forKey: .recallSeconds))
        defaultBreakRatio = try c.decode(Double.self, forKey: .defaultBreakRatio)
        focusGuard = try c.decodeIfPresent(FocusGuardConfiguration.self, forKey: .focusGuard) ?? .default
        cuesEnabled = try c.decodeIfPresent(Bool.self, forKey: .cuesEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(primeSeconds, forKey: .primeSeconds)
        try c.encode(recallSeconds, forKey: .recallSeconds)
        try c.encode(defaultBreakRatio, forKey: .defaultBreakRatio)
        try c.encode(focusGuard, forKey: .focusGuard)
        try c.encode(cuesEnabled, forKey: .cuesEnabled)
    }
}

public struct Profile: Equatable, Sendable {
    public var breakRatio: Double
    public var sessionCount: Int
    public var totalFocusSeconds: TimeInterval
    public var recentFocusSeconds: [TimeInterval]
    public var lastNote: String?
    public var lastIntention: String

    public static let `default` = Profile(
        breakRatio: Config.default.defaultBreakRatio,
        sessionCount: 0,
        totalFocusSeconds: 0,
        recentFocusSeconds: [],
        lastNote: nil,
        lastIntention: ""
    )

    public init(
        breakRatio: Double,
        sessionCount: Int,
        totalFocusSeconds: TimeInterval,
        recentFocusSeconds: [TimeInterval],
        lastNote: String?,
        lastIntention: String
    ) {
        self.breakRatio = breakRatio
        self.sessionCount = sessionCount
        self.totalFocusSeconds = totalFocusSeconds
        self.recentFocusSeconds = recentFocusSeconds
        self.lastNote = lastNote
        self.lastIntention = lastIntention
    }
}

extension Profile: Codable {
    enum CodingKeys: String, CodingKey {
        case breakRatio, sessionCount, totalFocusSeconds, recentFocusSeconds, lastNote, lastIntention
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        breakRatio = try c.decode(Double.self, forKey: .breakRatio)
        sessionCount = try c.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        totalFocusSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .totalFocusSeconds) ?? 0
        recentFocusSeconds = try c.decodeIfPresent([TimeInterval].self, forKey: .recentFocusSeconds) ?? []
        lastNote = try c.decodeIfPresent(String.self, forKey: .lastNote)
        lastIntention = try c.decodeIfPresent(String.self, forKey: .lastIntention) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(breakRatio, forKey: .breakRatio)
        try c.encode(sessionCount, forKey: .sessionCount)
        try c.encode(totalFocusSeconds, forKey: .totalFocusSeconds)
        try c.encode(recentFocusSeconds, forKey: .recentFocusSeconds)
        try c.encodeIfPresent(lastNote, forKey: .lastNote)
        try c.encode(lastIntention, forKey: .lastIntention)
    }
}

/// Product phase. Paused recovery is a wrapper (`pausedAt`), not a phase.
public enum SessionPhase: String, Codable, Sendable {
    case prime
    case focus
    case onBreak = "break"
    case recall
    case closeBeat
}

public struct CaptureItem: Codable, Equatable, Sendable {
    public var text: String
    public var createdAt: Date

    public init(text: String, createdAt: Date) {
        self.text = text
        self.createdAt = createdAt
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public var id: UUID
    public var intention: String
    public var phase: SessionPhase
    public var breakRatio: Double
    public var startedAt: Date
    public var phaseStartedAt: Date
    /// Durable lower bound for recovery after a supported Continue rewrites
    /// phase clocks while retaining this session's UUID.
    public var lastResumedAt: Date?
    public var focusStartedAt: Date?
    public var focusEndedAt: Date?
    public var breakStartedAt: Date?
    public var breakDuration: TimeInterval?
    public var captures: [CaptureItem]
    public var primeDuration: TimeInterval
    public var recallDuration: TimeInterval
    public var recallText: String
    public var pausedAt: Date?
    public var frozenElapsed: TimeInterval?
    public var frozenRemaining: TimeInterval?

    public var isPaused: Bool { pausedAt != nil }

    public init(
        id: UUID,
        intention: String,
        phase: SessionPhase,
        breakRatio: Double,
        startedAt: Date,
        phaseStartedAt: Date,
        focusStartedAt: Date?,
        focusEndedAt: Date?,
        breakStartedAt: Date?,
        breakDuration: TimeInterval?,
        captures: [CaptureItem],
        primeDuration: TimeInterval,
        recallDuration: TimeInterval,
        recallText: String = "",
        pausedAt: Date? = nil,
        frozenElapsed: TimeInterval? = nil,
        frozenRemaining: TimeInterval? = nil,
        lastResumedAt: Date? = nil
    ) {
        self.id = id
        self.intention = intention
        self.phase = phase
        self.breakRatio = breakRatio
        self.startedAt = startedAt
        self.phaseStartedAt = phaseStartedAt
        self.lastResumedAt = lastResumedAt
        self.focusStartedAt = focusStartedAt
        self.focusEndedAt = focusEndedAt
        self.breakStartedAt = breakStartedAt
        self.breakDuration = breakDuration
        self.captures = captures
        self.primeDuration = primeDuration
        self.recallDuration = recallDuration
        self.recallText = recallText
        self.pausedAt = pausedAt
        self.frozenElapsed = frozenElapsed
        self.frozenRemaining = frozenRemaining
    }
}

extension SessionSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case id, intention, label, phase, state
        case breakRatio, startedAt, phaseStartedAt, lastResumedAt
        case focusStartedAt, focusEndedAt, encodingStartedAt, encodingEndedAt
        case breakStartedAt, breakDuration, captures
        case primeDuration, recallDuration, recallText
        case pausedAt, frozenElapsed, frozenRemaining, pausedElapsed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        intention =
            try c.decodeIfPresent(String.self, forKey: .intention)
            ?? c.decodeIfPresent(String.self, forKey: .label)
            ?? ""
        breakRatio = try c.decode(Double.self, forKey: .breakRatio)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        phaseStartedAt = try c.decode(Date.self, forKey: .phaseStartedAt)
        lastResumedAt = try c.decodeIfPresent(Date.self, forKey: .lastResumedAt)
        focusStartedAt =
            try c.decodeIfPresent(Date.self, forKey: .focusStartedAt)
            ?? c.decodeIfPresent(Date.self, forKey: .encodingStartedAt)
        focusEndedAt =
            try c.decodeIfPresent(Date.self, forKey: .focusEndedAt)
            ?? c.decodeIfPresent(Date.self, forKey: .encodingEndedAt)
        breakStartedAt = try c.decodeIfPresent(Date.self, forKey: .breakStartedAt)
        breakDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .breakDuration)
        captures = try c.decodeIfPresent([CaptureItem].self, forKey: .captures) ?? []
        primeDuration = try c.decode(TimeInterval.self, forKey: .primeDuration)
        recallDuration = Config.migratedRecall(try c.decode(TimeInterval.self, forKey: .recallDuration))
        recallText = try c.decodeIfPresent(String.self, forKey: .recallText) ?? ""
        pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
        frozenElapsed = try c.decodeIfPresent(TimeInterval.self, forKey: .frozenElapsed)
        frozenRemaining = try c.decodeIfPresent(TimeInterval.self, forKey: .frozenRemaining)

        let legacyState = try c.decodeIfPresent(String.self, forKey: .state)
        if let phase = try c.decodeIfPresent(SessionPhase.self, forKey: .phase) {
            self.phase = phase
        } else {
            self.phase = Self.mapLegacyState(legacyState)
        }

        if legacyState == "paused" {
            if pausedAt == nil {
                pausedAt = phaseStartedAt
            }
            if frozenElapsed == nil {
                frozenElapsed = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedElapsed)
            }
            if self.phase != .focus {
                self.phase = .focus
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(intention, forKey: .intention)
        try c.encode(phase, forKey: .phase)
        try c.encode(breakRatio, forKey: .breakRatio)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(phaseStartedAt, forKey: .phaseStartedAt)
        try c.encodeIfPresent(lastResumedAt, forKey: .lastResumedAt)
        try c.encodeIfPresent(focusStartedAt, forKey: .focusStartedAt)
        try c.encodeIfPresent(focusEndedAt, forKey: .focusEndedAt)
        try c.encodeIfPresent(breakStartedAt, forKey: .breakStartedAt)
        try c.encodeIfPresent(breakDuration, forKey: .breakDuration)
        try c.encode(captures, forKey: .captures)
        try c.encode(primeDuration, forKey: .primeDuration)
        try c.encode(recallDuration, forKey: .recallDuration)
        try c.encode(recallText, forKey: .recallText)
        try c.encodeIfPresent(pausedAt, forKey: .pausedAt)
        try c.encodeIfPresent(frozenElapsed, forKey: .frozenElapsed)
        try c.encodeIfPresent(frozenRemaining, forKey: .frozenRemaining)
    }

    private static func mapLegacyState(_ raw: String?) -> SessionPhase {
        switch raw {
        case "priming", "prime": return .prime
        case "encoding", "focus", "paused": return .focus
        case "onBreak", "break": return .onBreak
        case "recall": return .recall
        case "closeBeat": return .closeBeat
        default: return .prime
        }
    }
}

public struct CompletedSession: Equatable, Sendable {
    public var id: UUID
    public var intention: String
    public var focusSeconds: TimeInterval
    public var breakSeconds: TimeInterval
    public var captureCount: Int
    public var captures: [CaptureItem]
    public var recallText: String?
    public var endedAt: Date

    public init(
        id: UUID,
        intention: String,
        focusSeconds: TimeInterval,
        breakSeconds: TimeInterval,
        captureCount: Int,
        recallText: String?,
        endedAt: Date,
        captures: [CaptureItem] = []
    ) {
        self.id = id
        self.intention = intention
        self.focusSeconds = focusSeconds
        self.breakSeconds = breakSeconds
        self.captureCount = captureCount
        self.captures = captures
        self.recallText = recallText
        self.endedAt = endedAt
    }
}

extension CompletedSession: Codable {
    enum CodingKeys: String, CodingKey {
        case id, intention, label, focusSeconds, breakSeconds, captureCount, captures, recallText, endedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        intention =
            try c.decodeIfPresent(String.self, forKey: .intention)
            ?? c.decodeIfPresent(String.self, forKey: .label)
            ?? ""
        focusSeconds = try c.decode(TimeInterval.self, forKey: .focusSeconds)
        breakSeconds = try c.decode(TimeInterval.self, forKey: .breakSeconds)
        captures = try c.decodeIfPresent([CaptureItem].self, forKey: .captures) ?? []
        captureCount = try c.decodeIfPresent(Int.self, forKey: .captureCount) ?? captures.count
        recallText = try c.decodeIfPresent(String.self, forKey: .recallText)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(intention, forKey: .intention)
        try c.encode(focusSeconds, forKey: .focusSeconds)
        try c.encode(breakSeconds, forKey: .breakSeconds)
        try c.encode(captureCount, forKey: .captureCount)
        try c.encode(captures, forKey: .captures)
        try c.encodeIfPresent(recallText, forKey: .recallText)
        try c.encode(endedAt, forKey: .endedAt)
    }
}

public enum HistoryOrder {
    public static func newestFirst(_ sessions: [CompletedSession]) -> [CompletedSession] {
        sessions.sorted { lhs, rhs in
            if lhs.endedAt != rhs.endedAt {
                return lhs.endedAt > rhs.endedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

public struct World: Codable, Equatable, Sendable {
    public var live: SessionSnapshot?
    public var profile: Profile
    public var config: Config
    public var history: [CompletedSession]

    public static let empty = World(
        live: nil,
        profile: .default,
        config: .default,
        history: []
    )

    public init(live: SessionSnapshot?, profile: Profile, config: Config, history: [CompletedSession]) {
        self.live = live
        self.profile = profile
        self.config = config
        self.history = history
    }

    public func todayFocusSeconds(now: Date, calendar: Calendar = .current) -> TimeInterval {
        let start = calendar.startOfDay(for: now)
        return history.reduce(0) { partial, session in
            guard session.endedAt >= start else { return partial }
            let sum = partial + session.focusSeconds
            if sum.isInfinite, partial.isFinite, session.focusSeconds.isFinite {
                return sum.sign == .minus ? -.greatestFiniteMagnitude : .greatestFiniteMagnitude
            }
            return sum
        }
    }
}

public enum Event: Equatable, Sendable {
    case start(intention: String)
    case skip
    case stopFocus
    case capture(String)
    case setRecallText(String)
    case pauseForRecovery
    case `continue`
    case restart
    case cancel
    case configureFocusGuard(FocusGuardConfiguration)
    case setCuesEnabled(Bool)
    case setLastIntention(String)
}

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case alreadyRunning
    case nothingRunning
    case notFocus
    case notPaused
    case cannotCapture
    case emptyCapture
    case cannotSetRecallText
    case notIdle

    public var description: String {
        switch self {
        case .alreadyRunning: return "A session is already running."
        case .nothingRunning: return "No session is running."
        case .notFocus: return "You can only stop while focusing."
        case .notPaused: return "Session is not paused."
        case .cannotCapture: return "You can only park a thought while focusing."
        case .emptyCapture: return "Capture text is empty."
        case .cannotSetRecallText: return "You can only write recall during recall."
        case .notIdle: return "You can only change Focus Guard while idle."
        }
    }
}

public enum AttentionCue {
    /// Prime ended, focus stopped, break ended, recall ended.
    public static func shouldPlay(from: SessionPhase?, to: SessionPhase?) -> Bool {
        switch (from, to) {
        case (.prime, .focus), (.focus, .onBreak), (.onBreak, .recall), (.recall, .closeBeat):
            return true
        default:
            return false
        }
    }
}

public struct SessionStatus: Equatable, Sendable {
    public var phase: SessionPhase?
    public var isPaused: Bool
    public var intention: String
    public var lastIntention: String
    public var elapsed: TimeInterval
    public var remaining: TimeInterval?
    public var phaseDuration: TimeInterval?
    public var focusSeconds: TimeInterval
    public var breakSeconds: TimeInterval?
    public var earnedBreakSeconds: TimeInterval
    public var captures: [CaptureItem]
    public var recallText: String
    public var todayFocusSeconds: TimeInterval
    public var ratio: Double

    public var isIdle: Bool { phase == nil }

    public init(
        phase: SessionPhase?,
        isPaused: Bool,
        intention: String,
        lastIntention: String,
        elapsed: TimeInterval,
        remaining: TimeInterval?,
        phaseDuration: TimeInterval?,
        focusSeconds: TimeInterval,
        breakSeconds: TimeInterval?,
        earnedBreakSeconds: TimeInterval,
        captures: [CaptureItem],
        recallText: String,
        todayFocusSeconds: TimeInterval,
        ratio: Double
    ) {
        self.phase = phase
        self.isPaused = isPaused
        self.intention = intention
        self.lastIntention = lastIntention
        self.elapsed = elapsed
        self.remaining = remaining
        self.phaseDuration = phaseDuration
        self.focusSeconds = focusSeconds
        self.breakSeconds = breakSeconds
        self.earnedBreakSeconds = earnedBreakSeconds
        self.captures = captures
        self.recallText = recallText
        self.todayFocusSeconds = todayFocusSeconds
        self.ratio = ratio
    }
}

/// Local notification delay while the process is suspended. Nil for Focus or paused.
public enum TimedNotice {
    public static func remainingToSchedule(_ status: SessionStatus) -> TimeInterval? {
        if status.isPaused { return nil }
        switch status.phase {
        case .prime, .onBreak, .recall:
            let remaining = status.remaining ?? 0
            return remaining > 0.05 ? remaining : nil
        default:
            return nil
        }
    }

    public static func copy(for phase: SessionPhase?) -> (title: String, body: String) {
        switch phase {
        case .focus:
            return ("Flowmo", "Prime ended.")
        case .onBreak:
            return ("Flowmo", "Focus stopped. Break earned.")
        case .recall:
            return ("Flowmo", "Break ended.")
        case .closeBeat:
            return ("Flowmo", "Reflection ended.")
        default:
            return ("Flowmo", "Phase changed.")
        }
    }
}
