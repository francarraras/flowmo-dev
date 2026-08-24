import Darwin
import Foundation

public enum EvidenceSignal: String, Codable, CaseIterable, Hashable, Sendable {
    case guardPromptOffered = "focus_guard_resumption_v1.prompt_offered_after_confirmed_hide"
    case guardStayFocusedChosen = "focus_guard_resumption_v1.stay_focused_chosen"
    case guardOpenOnceChosen = "focus_guard_resumption_v1.open_once_chosen"
    case guardOpenOnceActivationAccepted = "focus_guard_resumption_v1.open_once_activation_accepted"
    case guardOpenOnceNotAccepted = "focus_guard_resumption_v1.open_once_not_accepted"
    case guardInterceptionFailedBeforePrompt =
        "focus_guard_resumption_v1.interception_failed_before_prompt"
    case guardResumptionEligible = "focus_guard_resumption_v1.resumption_eligible"
    case guardResumptionIneligible = "focus_guard_resumption_v1.resumption_ineligible"
    case guardResumptionTreatmentDisabled =
        "focus_guard_resumption_v1.resumption_not_attempted_treatment_disabled"
    case guardResumptionRequestAccepted =
        "focus_guard_resumption_v1.resumption_activation_request_accepted"
    case guardResumptionConfirmed = "focus_guard_resumption_v1.resumption_confirmed"
    case guardResumptionRejected = "focus_guard_resumption_v1.resumption_activation_rejected"
    case guardResumptionTimedOut = "focus_guard_resumption_v1.resumption_timed_out"
    case guardResumptionResolutionMismatch =
        "focus_guard_resumption_v1.resumption_resolution_identity_mismatch"
    case guardResumptionActivationMismatch =
        "focus_guard_resumption_v1.resumption_activation_identity_mismatch"
}

/// Semantic observations emitted by the Focus Guard adapter. Each case owns
/// the only valid atomic counter batch for that product outcome.
public enum FocusGuardEvidenceEvent: Equatable, Sendable {
    case promptOfferedAfterConfirmedHide
    case stayFocusedResumptionIneligible
    case stayFocusedResumptionTreatmentDisabled
    case stayFocusedResumptionAttemptAccepted
    case stayFocusedResumptionRejected
    case stayFocusedResumptionResolutionMismatch
    case resumptionConfirmed
    case resumptionTimedOut
    case resumptionActivationMismatch
    case openOnceActivationAccepted
    case openOnceNotAccepted
    case interceptionFailedBeforePrompt

    fileprivate var signals: Set<EvidenceSignal> {
        switch self {
        case .promptOfferedAfterConfirmedHide:
            [.guardPromptOffered]
        case .stayFocusedResumptionIneligible:
            [.guardStayFocusedChosen, .guardResumptionIneligible]
        case .stayFocusedResumptionTreatmentDisabled:
            [.guardStayFocusedChosen, .guardResumptionTreatmentDisabled]
        case .stayFocusedResumptionAttemptAccepted:
            [
                .guardStayFocusedChosen,
                .guardResumptionEligible,
                .guardResumptionRequestAccepted,
            ]
        case .stayFocusedResumptionRejected:
            [
                .guardStayFocusedChosen,
                .guardResumptionEligible,
                .guardResumptionRejected,
            ]
        case .stayFocusedResumptionResolutionMismatch:
            [
                .guardStayFocusedChosen,
                .guardResumptionIneligible,
                .guardResumptionResolutionMismatch,
            ]
        case .resumptionConfirmed:
            [.guardResumptionConfirmed]
        case .resumptionTimedOut:
            [.guardResumptionTimedOut]
        case .resumptionActivationMismatch:
            [.guardResumptionActivationMismatch]
        case .openOnceActivationAccepted:
            [.guardOpenOnceChosen, .guardOpenOnceActivationAccepted]
        case .openOnceNotAccepted:
            [.guardOpenOnceChosen, .guardOpenOnceNotAccepted]
        case .interceptionFailedBeforePrompt:
            [.guardInterceptionFailedBeforePrompt]
        }
    }
}

public enum EvidenceDropReason: String, Codable, Equatable, Sendable {
    case busy
    case unavailable
    case invalidOrUnsupported = "invalid_or_unsupported"
}

public enum EvidenceRecordResult: Equatable, Sendable {
    case recorded
    case dropped(EvidenceDropReason)
}

public struct FlowmoEvidenceReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumCountPerCounter: UInt64 = 10_000_000
    public static let maximumPendingRecords = 16

    public enum MeasurementPlan: String, Codable, Equatable, Sendable {
        /// Mint a new case before changing event eligibility or timing, signal
        /// meaning/mapping, admission/drop policy, or either declared cap.
        case focusGuardResumptionV1 = "focus_guard_resumption_v1"
    }

    public enum Limitation: String, Codable, CaseIterable, Equatable, Sendable {
        case aggregateCountsOnly = "aggregate_counts_only"
        case noActivityTimestamps = "no_activity_timestamps"
        case noSessionLinkage = "no_session_linkage"
        case descriptiveNotOutcomeEvidence = "descriptive_not_outcome_evidence"
        case recordingCompletenessUnknown = "recording_completeness_unknown"
        case boundedBufferMayDropRecords = "bounded_buffer_may_drop_records"
        case rawCountsAreNotValidRates = "raw_counts_are_not_valid_rates"
        case countersMaySaturate = "counters_may_saturate"
        case recordedPathsArePossiblySaturatedLowerBounds =
            "recorded_paths_are_possibly_saturated_lower_bounds"
        case promptOfferDoesNotConfirmSeen = "prompt_offer_does_not_confirm_seen"
        case activationAcceptedDoesNotConfirmFrontmost =
            "activation_accepted_does_not_confirm_frontmost"
        case resumptionConfirmedMeansMatchingProcessOnly =
            "resumption_confirmed_means_matching_process_only"
        case resumptionDoesNotConfirmWindowDocumentOrWorkContext =
            "resumption_does_not_confirm_window_document_or_work_context"
        case pendingResumptionMayLackTerminalObservation =
            "pending_resumption_may_lack_terminal_observation"
        case comparePredeclaredSnapshotDeltasWithinSamePlanOnly =
            "compare_predeclared_snapshot_deltas_within_same_plan_only"
        case snapshotDeltasRequireSameStoreWithoutReset =
            "snapshot_deltas_require_same_store_without_reset"
        case snapshotEndMustBeLaterAndCountsNondecreasing =
            "snapshot_end_must_be_later_and_counts_nondecreasing"
        case saturatedSnapshotDeltasAreCensored =
            "saturated_snapshot_deltas_are_censored"
    }

    public struct Counter: Codable, Equatable, Sendable {
        public let signal: EvidenceSignal
        public let count: UInt64

        public init(signal: EvidenceSignal, count: UInt64) {
            self.signal = signal
            self.count = count
        }
    }

    public let schemaVersion: Int
    public let generatedAt: Date
    public let measurementPlan: MeasurementPlan
    public let maximumCountPerCounter: UInt64
    public let maximumPendingRecords: Int
    public let counters: [Counter]
    public let limitations: [Limitation]

    public init(generatedAt: Date, counters: [Counter]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.measurementPlan = .focusGuardResumptionV1
        self.maximumCountPerCounter = Self.maximumCountPerCounter
        self.maximumPendingRecords = Self.maximumPendingRecords
        self.counters = counters
        self.limitations = Limitation.allCases
    }
}

public struct LocalEvidence: Sendable {
    private static let storageSchemaVersion = 2
    private static let evidenceFilename = "evidence.json"
    private static let lockFilename = "evidence.lock"
    private static let temporaryWritePrefix = ".evidence.write-"
    private static let temporaryWriteSuffix = ".tmp"
    private static let maximumFileBytes = 64 * 1024
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    @discardableResult
    public func record(_ event: FocusGuardEvidenceEvent) -> EvidenceRecordResult {
        do {
            return try withLock(nonBlocking: true) {
                var counts = try loadCountsUnlocked()
                for signal in event.signals {
                    let current = counts[signal, default: 0]
                    counts[signal] =
                        current < FlowmoEvidenceReport.maximumCountPerCounter
                        ? current + 1
                        : FlowmoEvidenceReport.maximumCountPerCounter
                }
                try validateAtomicOpenCounts(counts)
                try validateResumptionCounts(counts)
                try saveCountsUnlocked(counts)
                return .recorded
            }
        } catch EvidenceStorageError.busy {
            return .dropped(.busy)
        } catch EvidenceStorageError.invalidOrUnsupported {
            return .dropped(.invalidOrUnsupported)
        } catch {
            return .dropped(.unavailable)
        }
    }

    public func export(generatedAt: Date) throws -> Data {
        guard generatedAt.timeIntervalSince1970.isFinite else {
            throw EvidenceStorageError.invalidOrUnsupported
        }
        return try withLock(nonBlocking: true) {
            let counts = try loadCountsUnlocked()
            let report = FlowmoEvidenceReport(
                generatedAt: generatedAt,
                counters: EvidenceSignal.allCases.map { signal in
                    FlowmoEvidenceReport.Counter(signal: signal, count: counts[signal, default: 0])
                }
            )
            return try JSONEncoder.flowmo.encode(report)
        }
    }

    func deleteOwnedData() throws -> LocalEvidenceDeletionResult {
        do {
            return try withLock(nonBlocking: true) {
                let artifacts: [URL]
                do {
                    artifacts = try ownedArtifactURLsUnlocked()
                } catch {
                    throw LocalEvidenceDeletionError(
                        removedArtifactURLs: [],
                        remainingArtifactURLs: [],
                        remainingArtifactsKnown: false,
                        reason: "Evidence artifacts could not be enumerated: \(error.localizedDescription)"
                    )
                }

                var removed: [URL] = []
                var failures: [(url: URL, reason: String)] = []
                for artifact in artifacts {
                    if unlink(artifact.path) == 0 {
                        removed.append(artifact)
                    } else if errno != ENOENT {
                        failures.append((artifact, Self.posixMessage()))
                    }
                }

                guard failures.isEmpty else {
                    throw LocalEvidenceDeletionError(
                        removedArtifactURLs: removed,
                        remainingArtifactURLs: failures.map(\.url),
                        remainingArtifactsKnown: true,
                        reason: failures.map { "\($0.url.lastPathComponent): \($0.reason)" }.joined(separator: "; ")
                    )
                }
                return LocalEvidenceDeletionResult(removedArtifactURLs: removed)
            }
        } catch let error as LocalEvidenceDeletionError {
            throw error
        } catch {
            throw LocalEvidenceDeletionError(
                removedArtifactURLs: [],
                remainingArtifactURLs: [],
                remainingArtifactsKnown: false,
                reason: "Evidence deletion could not be completed: \(error.localizedDescription)"
            )
        }
    }

    private var evidenceURL: URL {
        root.appendingPathComponent(Self.evidenceFilename)
    }

    private var lockURL: URL {
        root.appendingPathComponent(Self.lockFilename)
    }

    private func loadCountsUnlocked() throws -> [EvidenceSignal: UInt64] {
        guard let data = try readEvidenceDataUnlocked() else { return [:] }
        try validateRawDocument(data)

        let document: EvidenceDocument
        do {
            document = try JSONDecoder.flowmo.decode(EvidenceDocument.self, from: data)
        } catch {
            throw EvidenceStorageError.invalidOrUnsupported
        }
        guard document.schemaVersion == Self.storageSchemaVersion else {
            throw EvidenceStorageError.invalidOrUnsupported
        }
        guard document.measurementPlan == .focusGuardResumptionV1 else {
            throw EvidenceStorageError.invalidOrUnsupported
        }
        guard document.counters.count <= EvidenceSignal.allCases.count else {
            throw EvidenceStorageError.invalidOrUnsupported
        }

        var counts: [EvidenceSignal: UInt64] = [:]
        for counter in document.counters {
            guard counter.count <= FlowmoEvidenceReport.maximumCountPerCounter,
                counts[counter.signal] == nil
            else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
            counts[counter.signal] = counter.count
        }
        try validateAtomicOpenCounts(counts)
        try validateResumptionCounts(counts)
        return counts
    }

    private func validateAtomicOpenCounts(_ counts: [EvidenceSignal: UInt64]) throws {
        let chosen = counts[.guardOpenOnceChosen, default: 0]
        let accepted = counts[.guardOpenOnceActivationAccepted, default: 0]
        let notAccepted = counts[.guardOpenOnceNotAccepted, default: 0]
        let (terminalTotal, overflowed) = accepted.addingReportingOverflow(notAccepted)
        guard !overflowed, accepted <= chosen, notAccepted <= chosen else {
            throw EvidenceStorageError.invalidOrUnsupported
        }

        let maximum = FlowmoEvidenceReport.maximumCountPerCounter
        if chosen < maximum {
            guard terminalTotal == chosen else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
        } else {
            guard terminalTotal >= maximum else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
        }
    }

    private func validateResumptionCounts(_ counts: [EvidenceSignal: UInt64]) throws {
        let maximum = FlowmoEvidenceReport.maximumCountPerCounter
        let chosen = counts[.guardStayFocusedChosen, default: 0]
        let eligible = counts[.guardResumptionEligible, default: 0]
        let ineligible = counts[.guardResumptionIneligible, default: 0]
        let treatmentDisabled = counts[.guardResumptionTreatmentDisabled, default: 0]
        let requestAccepted = counts[.guardResumptionRequestAccepted, default: 0]
        let rejected = counts[.guardResumptionRejected, default: 0]
        let confirmed = counts[.guardResumptionConfirmed, default: 0]
        let timedOut = counts[.guardResumptionTimedOut, default: 0]
        let resolutionMismatch = counts[.guardResumptionResolutionMismatch, default: 0]
        let activationMismatch = counts[.guardResumptionActivationMismatch, default: 0]

        guard eligible <= chosen, ineligible <= chosen, treatmentDisabled <= chosen,
            requestAccepted <= eligible, rejected <= eligible,
            confirmed <= requestAccepted, timedOut <= requestAccepted,
            resolutionMismatch <= ineligible, activationMismatch <= requestAccepted
        else {
            throw EvidenceStorageError.invalidOrUnsupported
        }

        if chosen < maximum {
            let (partlyClassified, firstOverflow) = eligible.addingReportingOverflow(ineligible)
            let (classified, secondOverflow) = partlyClassified.addingReportingOverflow(
                treatmentDisabled
            )
            guard !firstOverflow, !secondOverflow, classified == chosen else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
        }
        if eligible < maximum {
            let (classified, overflowed) = requestAccepted.addingReportingOverflow(rejected)
            guard !overflowed, classified == eligible else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
        }
        if requestAccepted < maximum {
            let terminal = confirmed + timedOut + activationMismatch
            guard terminal <= requestAccepted else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
        }
    }

    private func saveCountsUnlocked(_ counts: [EvidenceSignal: UInt64]) throws {
        let document = EvidenceDocument(
            schemaVersion: Self.storageSchemaVersion,
            measurementPlan: .focusGuardResumptionV1,
            counters: EvidenceSignal.allCases.map { signal in
                StoredCounter(
                    signal: signal,
                    count: min(
                        counts[signal, default: 0],
                        FlowmoEvidenceReport.maximumCountPerCounter
                    )
                )
            }
        )
        let data: Data
        do {
            data = try JSONEncoder.flowmo.encode(document)
        } catch {
            throw EvidenceStorageError.unavailable
        }
        guard data.count <= Self.maximumFileBytes else {
            throw EvidenceStorageError.invalidOrUnsupported
        }

        try rejectUnsafeExistingEvidenceTargetUnlocked()
        let temporary = root.appendingPathComponent(
            "\(Self.temporaryWritePrefix)\(UUID().uuidString)\(Self.temporaryWriteSuffix)"
        )
        let fd = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard fd >= 0 else { throw EvidenceStorageError.unavailable }
        var keepTemporary = true
        defer {
            close(fd)
            if keepTemporary { _ = unlink(temporary.path) }
        }

        guard fchmod(fd, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            throw EvidenceStorageError.unavailable
        }
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let amount = Darwin.write(fd, baseAddress.advanced(by: offset), bytes.count - offset)
                if amount < 0 {
                    if errno == EINTR { continue }
                    throw EvidenceStorageError.unavailable
                }
                guard amount > 0 else { throw EvidenceStorageError.unavailable }
                offset += amount
            }
        }
        guard fsync(fd) == 0 else { throw EvidenceStorageError.unavailable }
        guard rename(temporary.path, evidenceURL.path) == 0 else {
            throw EvidenceStorageError.unavailable
        }
        keepTemporary = false
    }

    private func readEvidenceDataUnlocked() throws -> Data? {
        let fd = open(evidenceURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw EvidenceStorageError.invalidOrUnsupported }
            throw EvidenceStorageError.unavailable
        }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0 else { throw EvidenceStorageError.unavailable }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_size >= 0 else {
            throw EvidenceStorageError.invalidOrUnsupported
        }
        guard info.st_size <= Self.maximumFileBytes else {
            throw EvidenceStorageError.invalidOrUnsupported
        }

        var data = Data()
        data.reserveCapacity(min(Int(info.st_size), Self.maximumFileBytes))
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let capacity = Self.maximumFileBytes + 1 - data.count
            guard capacity > 0 else { throw EvidenceStorageError.invalidOrUnsupported }
            let amount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fd, bytes.baseAddress, min(bytes.count, capacity))
            }
            if amount == 0 { break }
            if amount < 0 {
                if errno == EINTR { continue }
                throw EvidenceStorageError.unavailable
            }
            data.append(contentsOf: buffer.prefix(amount))
            guard data.count <= Self.maximumFileBytes else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
        }
        return data
    }

    private func validateRawDocument(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw EvidenceStorageError.invalidOrUnsupported
        }
        guard let root = object as? [String: Any],
            Set(root.keys) == ["schemaVersion", "measurementPlan", "counters"],
            let counters = root["counters"] as? [Any], counters.count <= EvidenceSignal.allCases.count
        else {
            throw EvidenceStorageError.invalidOrUnsupported
        }
        for rawCounter in counters {
            guard let counter = rawCounter as? [String: Any], Set(counter.keys) == ["signal", "count"] else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
        }
    }

    private func rejectUnsafeExistingEvidenceTargetUnlocked() throws {
        var info = stat()
        if lstat(evidenceURL.path, &info) == 0 {
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                throw EvidenceStorageError.invalidOrUnsupported
            }
            return
        }
        guard errno == ENOENT else { throw EvidenceStorageError.unavailable }
    }

    private func ownedArtifactURLsUnlocked() throws -> [URL] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        )
        return
            entries
            .filter { entry in
                entry.lastPathComponent == Self.evidenceFilename
                    || Self.isOwnedTemporaryWrite(entry.lastPathComponent)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isOwnedTemporaryWrite(_ name: String) -> Bool {
        guard name.hasPrefix(temporaryWritePrefix), name.hasSuffix(temporaryWriteSuffix) else {
            return false
        }
        let tokenStart = name.index(name.startIndex, offsetBy: temporaryWritePrefix.count)
        let tokenEnd = name.index(name.endIndex, offsetBy: -temporaryWriteSuffix.count)
        guard tokenStart < tokenEnd else { return false }
        return UUID(uuidString: String(name[tokenStart..<tokenEnd])) != nil
    }

    private func withLock<T>(nonBlocking: Bool, _ body: () throws -> T) throws -> T {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw EvidenceStorageError.unavailable
        }
        let fd = open(
            lockURL.path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard fd >= 0 else { throw EvidenceStorageError.unavailable }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            fchmod(fd, mode_t(S_IRUSR | S_IWUSR)) == 0
        else {
            throw EvidenceStorageError.unavailable
        }

        let operation = LOCK_EX | (nonBlocking ? LOCK_NB : 0)
        guard flock(fd, operation) == 0 else {
            if nonBlocking, errno == EWOULDBLOCK || errno == EAGAIN {
                throw EvidenceStorageError.busy
            }
            throw EvidenceStorageError.unavailable
        }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    private static func posixMessage() -> String {
        String(cString: strerror(errno))
    }
}

struct LocalEvidenceDeletionResult: Equatable, Sendable {
    let removedArtifactURLs: [URL]
}

struct LocalEvidenceDeletionError: LocalizedError, Equatable, Sendable {
    let removedArtifactURLs: [URL]
    let remainingArtifactURLs: [URL]
    let remainingArtifactsKnown: Bool
    let reason: String

    var errorDescription: String? {
        if remainingArtifactsKnown {
            return
                "Aggregate evidence deletion was incomplete; \(remainingArtifactURLs.count) artifacts remain: \(reason)."
        }
        return "Aggregate evidence deletion could not be verified: \(reason)."
    }
}

private struct EvidenceDocument: Codable {
    let schemaVersion: Int
    let measurementPlan: FlowmoEvidenceReport.MeasurementPlan
    let counters: [StoredCounter]
}

private struct StoredCounter: Codable {
    let signal: EvidenceSignal
    let count: UInt64
}

private enum EvidenceStorageError: LocalizedError {
    case busy
    case unavailable
    case invalidOrUnsupported

    var errorDescription: String? {
        switch self {
        case .busy: "Aggregate evidence is busy."
        case .unavailable: "Aggregate evidence is unavailable."
        case .invalidOrUnsupported: "Aggregate evidence is invalid or uses an unsupported schema."
        }
    }
}
