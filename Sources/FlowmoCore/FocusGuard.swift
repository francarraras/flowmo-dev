import Foundation

public struct FocusGuardConfiguration: Equatable, Sendable {
    public var enabled: Bool
    public var bundleIdentifiers: [String]

    public static let `default` = FocusGuardConfiguration(enabled: false, bundleIdentifiers: [])

    public init(enabled: Bool = false, bundleIdentifiers: [String] = []) {
        self.enabled = enabled
        self.bundleIdentifiers = FocusGuard.normalize(bundleIdentifiers)
    }
}

extension FocusGuardConfiguration: Codable {
    enum CodingKeys: String, CodingKey {
        case enabled, bundleIdentifiers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        bundleIdentifiers = FocusGuard.normalize(
            try c.decodeIfPresent([String].self, forKey: .bundleIdentifiers) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(bundleIdentifiers, forKey: .bundleIdentifiers)
    }
}

public enum FocusGuardDemand: Equatable, Sendable {
    case inactive
    case active(sessionID: UUID, bundleIdentifiers: Set<String>)
}

public enum FocusGuardDecision: Equatable, Sendable {
    case ignore
    case intercept
    case allowedOnce
}

public struct FocusGuardRuntime: Equatable, Sendable {
    public var demand: FocusGuardDemand = .inactive
    public var allowedProcessID: Int32?
    public var interception: FocusGuardInterception?
    public var degraded: Bool = false

    public init() {}

    public mutating func setDemand(_ next: FocusGuardDemand) {
        if demand != next {
            allowedProcessID = nil
            interception = nil
            degraded = false
        }
        demand = next
        if case .inactive = next {
            allowedProcessID = nil
            interception = nil
        }
    }

    public mutating func activated(
        bundleID: String?,
        processID: Int32,
        displayName: String,
        isSelf: Bool
    ) -> FocusGuardDecision {
        guard case .active(_, let ids) = demand, !isSelf else { return .ignore }
        guard let bundleID, ids.contains(bundleID) else { return .ignore }
        if allowedProcessID == processID {
            return .allowedOnce
        }
        interception = FocusGuardInterception(
            bundleIdentifier: bundleID,
            processIdentifier: processID,
            displayName: displayName
        )
        return .intercept
    }

    public mutating func deactivated(processID: Int32) {
        if allowedProcessID == processID {
            allowedProcessID = nil
        }
    }

    public mutating func stayFocused() {
        interception = nil
    }

    public mutating func allowOnce() {
        if let interception {
            allowedProcessID = interception.processIdentifier
        }
        interception = nil
    }
}

public struct FocusGuardInterception: Equatable, Sendable {
    public var bundleIdentifier: String
    public var processIdentifier: Int32
    public var displayName: String

    public init(bundleIdentifier: String, processIdentifier: Int32, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.displayName = displayName
    }
}

public enum FocusGuard {
    public static let forbiddenBundleIdentifiers: Set<String> = [
        "app.flowmo.mac",
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.NotificationCenter",
    ]

    public static func normalize(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in ids {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            guard !forbiddenBundleIdentifiers.contains(id) else { continue }
            guard seen.insert(id).inserted else { continue }
            out.append(id)
        }
        return out.sorted()
    }

    public static func demand(world: World) -> FocusGuardDemand {
        let config = world.config.focusGuard
        guard config.enabled, !config.bundleIdentifiers.isEmpty else { return .inactive }
        guard let live = world.live, live.phase == .focus, !live.isPaused else { return .inactive }
        return .active(sessionID: live.id, bundleIdentifiers: Set(config.bundleIdentifiers))
    }

    public static func statusLine(world: World) -> String? {
        guard case .active(_, let ids) = demand(world: world) else { return nil }
        let n = ids.count
        return n == 1 ? "Guarding 1 app" : "Guarding \(n) apps"
    }
}
