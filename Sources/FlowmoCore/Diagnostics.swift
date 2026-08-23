import Foundation
import OSLog

/// Stable, privacy-safe identifiers for issues that may appear in UI, logs,
/// and a user-requested diagnostic report.
public enum FlowmoIssueCode: String, Codable, CaseIterable, Sendable {
    case storeUnavailable = "FLOWMO-STORE-001"
    case storeUnreadable = "FLOWMO-STORE-002"
    case persistenceFailed = "FLOWMO-STORE-003"
    case recoveryUnavailable = "FLOWMO-RECOVERY-001"
    case diagnosticExportFailed = "FLOWMO-EXPORT-001"
    case dataExportFailed = "FLOWMO-EXPORT-002"
    case resetFailed = "FLOWMO-RESET-001"
    case preserveAndResetFailed = "FLOWMO-RESET-002"
    case dataDeletionIncomplete = "FLOWMO-RESET-003"
}

public enum FlowmoDiagnosticOperation: String, Codable, Sendable {
    case appGroup = "app_group"
    case load = "load"
    case update = "update"
    case sync = "sync"
    case heartbeat = "heartbeat"
    case recoveryClaim = "recovery_claim"
    case recoveryHeartbeat = "recovery_heartbeat"
    case recoveryPause = "recovery_pause"
    case recoveryFinish = "recovery_finish"
    case dataExport = "data_export"
    case diagnosticExport = "diagnostic_export"
    case reset = "reset"
    case preserveAndReset = "preserve_and_reset"
}

public struct FlowmoIssueRecord: Codable, Equatable, Sendable {
    public let code: FlowmoIssueCode
    public let operation: FlowmoDiagnosticOperation
    public let occurredAt: Date

    public init(code: FlowmoIssueCode, operation: FlowmoDiagnosticOperation, occurredAt: Date) {
        self.code = code
        self.operation = operation
        self.occurredAt = occurredAt
    }
}

public struct FlowmoPresentedIssue: Identifiable, Equatable, Sendable {
    public var id: FlowmoIssueCode { code }
    public let code: FlowmoIssueCode

    public init(code: FlowmoIssueCode) {
        self.code = code
    }

    public var title: String {
        switch code {
        case .storeUnavailable: "Flowmo unavailable"
        case .storeUnreadable: "Data needs attention"
        case .persistenceFailed: "Changes weren’t saved"
        case .recoveryUnavailable: "Recovery needs attention"
        case .diagnosticExportFailed: "Couldn’t prepare diagnostics"
        case .dataExportFailed: "Couldn’t prepare data export"
        case .resetFailed: "Couldn’t delete data"
        case .preserveAndResetFailed: "Couldn’t preserve and reset"
        case .dataDeletionIncomplete: "Some recovery data remains"
        }
    }

    public var message: String {
        switch code {
        case .storeUnavailable:
            "Flowmo can’t access its local data right now. Try again."
        case .storeUnreadable:
            "Flowmo couldn’t read its local data. Retry, or preserve the original and reset."
        case .persistenceFailed:
            "Your latest change wasn’t saved. Flowmo kept the last saved state."
        case .recoveryUnavailable:
            "Flowmo couldn’t safely protect quit or sleep recovery. Retry before continuing."
        case .diagnosticExportFailed:
            "Flowmo couldn’t create the redacted diagnostic report."
        case .dataExportFailed:
            "Flowmo couldn’t create the full data export."
        case .resetFailed:
            "Flowmo couldn’t delete the current local data."
        case .preserveAndResetFailed:
            "Flowmo couldn’t preserve the original data and reset safely."
        case .dataDeletionIncomplete:
            "Your current Flowmo data was deleted, but some preserved recovery data couldn’t be removed."
        }
    }
}

public enum FlowmoExportResult {
    public static func isUserCancellation(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain
            && cocoaError.code == CocoaError.userCancelled.rawValue
    }
}

public enum FlowmoDiagnosticLog {
    private static let logger = Logger(subsystem: "app.flowmo", category: "diagnostics")

    public static func emit(_ code: FlowmoIssueCode, operation: FlowmoDiagnosticOperation) {
        logger.error(
            "issue_code=\(code.rawValue, privacy: .public) operation=\(operation.rawValue, privacy: .public)"
        )
    }
}

public enum FlowmoIssueClassifier {
    public static func persistenceFailure(_ error: Error) -> FlowmoIssueCode {
        if error is WorldValidationError {
            return .storeUnreadable
        }
        guard let storeError = error as? StoreError else {
            return .persistenceFailed
        }
        switch storeError {
        case .cannotOpenWorld, .cannotInspectWorld, .cannotReadWorld,
            .cannotDecodeWorld, .unsafeWorldTarget, .worldTooLarge:
            return .storeUnreadable
        case .lockFailed, .cannotWriteWorld, .cannotQuarantine,
            .worldIsValid, .worldMissing, .liveSessionPreventsReset:
            return .persistenceFailed
        }
    }
}

public struct FlowmoDiagnosticReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public struct AppMetadata: Codable, Equatable, Sendable {
        public let name: String
        public let version: String
        public let build: String
        public let operatingSystem: String
        public let platform: String

        public init(name: String, version: String, build: String, operatingSystem: String, platform: String) {
            self.name = name
            self.version = version
            self.build = build
            self.operatingSystem = operatingSystem
            self.platform = platform
        }
    }

    public struct SessionMetadata: Codable, Equatable, Sendable {
        public let phase: String
        public let paused: Bool

        public init(phase: String, paused: Bool) {
            self.phase = phase
            self.paused = paused
        }
    }

    public struct Counts: Codable, Equatable, Sendable {
        public let completedSessions: Int
        public let profileSessions: Int
        public let liveCaptures: Int
        public let completedCaptures: Int

        public init(completedSessions: Int, profileSessions: Int, liveCaptures: Int, completedCaptures: Int) {
            self.completedSessions = completedSessions
            self.profileSessions = profileSessions
            self.liveCaptures = liveCaptures
            self.completedCaptures = completedCaptures
        }
    }

    public let schemaVersion: Int
    public let generatedAt: Date
    public let app: AppMetadata
    public let session: SessionMetadata
    public let counts: Counts
    public let recentIssues: [FlowmoIssueRecord]

    public init(
        generatedAt: Date,
        app: AppMetadata,
        world: World,
        recentIssues: [FlowmoIssueRecord],
        storeAvailable: Bool = true
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.app = app
        self.session = SessionMetadata(
            phase: storeAvailable ? world.live?.phase.rawValue ?? "idle" : "unavailable",
            paused: storeAvailable ? world.live?.isPaused ?? false : false
        )
        self.counts = Counts(
            completedSessions: world.history.count,
            profileSessions: world.profile.sessionCount,
            liveCaptures: world.live?.captures.count ?? 0,
            completedCaptures: world.history.reduce(0) { total, session in
                let (sum, overflow) = total.addingReportingOverflow(session.captureCount)
                return overflow ? Int.max : sum
            }
        )
        self.recentIssues = Array(recentIssues.suffix(20))
    }

    public func encoded() throws -> Data {
        try JSONEncoder.flowmo.encode(self)
    }

    public static func currentAppMetadata(bundle: Bundle = .main) -> AppMetadata {
        let info = bundle.infoDictionary ?? [:]
        let name =
            info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
            ?? "Flowmo"
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        #if os(macOS)
            let platform = "macOS"
        #elseif os(iOS)
            let platform = "iOS"
        #else
            let platform = "unknown"
        #endif
        return AppMetadata(
            name: name,
            version: version,
            build: build,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            platform: platform
        )
    }
}
