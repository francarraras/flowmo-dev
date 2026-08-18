import Foundation

public struct Config: Codable, Equatable, Sendable {
    public var primeSeconds: TimeInterval
    public var recallSeconds: TimeInterval
    public var defaultBreakRatio: Double

    public static let `default` = Config(
        primeSeconds: 2 * 60,
        recallSeconds: 5 * 60,
        defaultBreakRatio: 5
    )

    public init(primeSeconds: TimeInterval, recallSeconds: TimeInterval, defaultBreakRatio: Double) {
        self.primeSeconds = primeSeconds
        self.recallSeconds = recallSeconds
        self.defaultBreakRatio = defaultBreakRatio
    }
}

public struct Profile: Codable, Equatable, Sendable {
    public var breakRatio: Double
    public var sessionCount: Int
    public var totalFocusSeconds: TimeInterval
    public var recentFocusSeconds: [TimeInterval]
    public var lastNote: String?

    public static let `default` = Profile(
        breakRatio: Config.default.defaultBreakRatio,
        sessionCount: 0,
        totalFocusSeconds: 0,
        recentFocusSeconds: [],
        lastNote: nil
    )

    public init(
        breakRatio: Double,
        sessionCount: Int,
        totalFocusSeconds: TimeInterval,
        recentFocusSeconds: [TimeInterval],
        lastNote: String?
    ) {
        self.breakRatio = breakRatio
        self.sessionCount = sessionCount
        self.totalFocusSeconds = totalFocusSeconds
        self.recentFocusSeconds = recentFocusSeconds
        self.lastNote = lastNote
    }
}

public enum SessionState: String, Codable, Sendable {
    case priming
    case encoding
    case paused
    case onBreak
    case recall
}

public struct CaptureItem: Codable, Equatable, Sendable {
    public var text: String
    public var createdAt: Date

    public init(text: String, createdAt: Date) {
        self.text = text
        self.createdAt = createdAt
    }
}

public struct SessionSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var state: SessionState
    public var breakRatio: Double
    public var startedAt: Date
    public var phaseStartedAt: Date
    public var encodingStartedAt: Date?
    public var encodingEndedAt: Date?
    public var pausedElapsed: TimeInterval?
    public var breakStartedAt: Date?
    public var breakDuration: TimeInterval?
    public var captures: [CaptureItem]
    public var primeDuration: TimeInterval
    public var recallDuration: TimeInterval
}

public struct CompletedSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var focusSeconds: TimeInterval
    public var breakSeconds: TimeInterval
    public var captureCount: Int
    public var endedAt: Date
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
}

public enum Event: Equatable, Sendable {
    case start(label: String)
    case pause
    case resume
    case stopEncoding
    case skip
    case cancel
    case capture(String)
}

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case alreadyRunning
    case nothingRunning
    case notEncoding
    case notPaused
    case cannotPause
    case cannotCapture
    case emptyCapture

    public var description: String {
        switch self {
        case .alreadyRunning: return "A session is already running. Stop or cancel it first."
        case .nothingRunning: return "No session is running."
        case .notEncoding: return "You can only stop while focusing."
        case .notPaused: return "Session is not paused."
        case .cannotPause: return "You can only pause while focusing."
        case .cannotCapture: return "You can only park a thought while focusing."
        case .emptyCapture: return "Capture text is empty."
        }
    }
}

public struct ViewStatus: Equatable, Sendable {
    public var state: SessionState
    public var label: String
    public var elapsed: TimeInterval
    public var remaining: TimeInterval?
    public var focusSeconds: TimeInterval
    public var breakSeconds: TimeInterval?
    public var captures: [CaptureItem]
    public var ratio: Double
}
