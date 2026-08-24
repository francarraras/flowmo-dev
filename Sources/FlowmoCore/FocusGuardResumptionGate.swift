import Foundation

public enum FocusGuardResumptionGate {
    public static let requiredEligibleAttempts = 60
    public static let maximumCollectionDays = 30
    public static let minimumReliability = 0.95
    public static let maximumFailureProportion = 0.05
    public static let confidenceLevel = 0.95

    public enum Decision: String, Equatable, Sendable {
        case pass
        case fail
        case inconclusive
        case invalid
    }

    public enum Reason: String, Equatable, Sendable {
        case incompatibleReport = "incompatible_report"
        case invalidSnapshotChronology = "invalid_snapshot_chronology"
        case collectionWindowExceeded = "collection_window_exceeded"
        case invalidCounters = "invalid_counters"
        case counterDecreased = "counter_decreased"
        case counterSaturated = "counter_saturated"
        case integrityIncident = "integrity_incident"
        case supervisedTallyMismatch = "supervised_tally_mismatch"
        case terminalOutcomesIncomplete = "terminal_outcomes_incomplete"
        case identityMismatch = "identity_mismatch"
        case treatmentAlreadyDisabled = "treatment_already_disabled"
        case reliabilityFailure = "reliability_failure"
        case minimumAttemptsNotReached = "minimum_attempts_not_reached"
        case plannedSampleExceeded = "planned_sample_exceeded"
    }

    public struct Evaluation: Equatable, Sendable {
        public let decision: Decision
        public let reasons: [Reason]
        public let supervisedEligibleAttempts: Int
        public let recordedEligibleAttempts: UInt64
        public let confirmedAttempts: UInt64
        public let recordedFailures: UInt64
        public let oneSidedFailureUpperBound: Double?

        public init(
            decision: Decision,
            reasons: [Reason],
            supervisedEligibleAttempts: Int,
            recordedEligibleAttempts: UInt64,
            confirmedAttempts: UInt64,
            recordedFailures: UInt64,
            oneSidedFailureUpperBound: Double?
        ) {
            self.decision = decision
            self.reasons = reasons
            self.supervisedEligibleAttempts = supervisedEligibleAttempts
            self.recordedEligibleAttempts = recordedEligibleAttempts
            self.confirmedAttempts = confirmedAttempts
            self.recordedFailures = recordedFailures
            self.oneSidedFailureUpperBound = oneSidedFailureUpperBound
        }
    }

    public static func evaluate(
        start: FlowmoEvidenceReport,
        end: FlowmoEvidenceReport,
        supervisedEligibleAttempts: Int,
        firstEligibleAttemptAt: Date,
        integrityIncident: Bool
    ) -> Evaluation {
        var invalidReasons: [Reason] = []

        guard reportsAreCompatible(start, end) else {
            return evaluation(
                .invalid,
                [.incompatibleReport],
                supervisedEligibleAttempts: supervisedEligibleAttempts
            )
        }
        guard start.generatedAt < firstEligibleAttemptAt,
            firstEligibleAttemptAt <= end.generatedAt
        else {
            return evaluation(
                .invalid,
                [.invalidSnapshotChronology],
                supervisedEligibleAttempts: supervisedEligibleAttempts
            )
        }
        if end.generatedAt.timeIntervalSince(firstEligibleAttemptAt)
            > Double(maximumCollectionDays * 24 * 60 * 60)
        {
            invalidReasons.append(.collectionWindowExceeded)
        }

        guard let startCounts = validatedCounts(start),
            let endCounts = validatedCounts(end)
        else {
            return evaluation(
                .invalid,
                invalidReasons + [.invalidCounters],
                supervisedEligibleAttempts: supervisedEligibleAttempts
            )
        }

        var deltas: [EvidenceSignal: UInt64] = [:]
        for signal in EvidenceSignal.allCases {
            let before = startCounts[signal, default: 0]
            let after = endCounts[signal, default: 0]
            guard after >= before else {
                return evaluation(
                    .invalid,
                    invalidReasons + [.counterDecreased],
                    supervisedEligibleAttempts: supervisedEligibleAttempts
                )
            }
            if after == FlowmoEvidenceReport.maximumCountPerCounter,
                !invalidReasons.contains(.counterSaturated)
            {
                invalidReasons.append(.counterSaturated)
            }
            deltas[signal] = after - before
        }
        if integrityIncident {
            invalidReasons.append(.integrityIncident)
        }

        let eligible = deltas[.guardResumptionEligible, default: 0]
        let requestAccepted = deltas[.guardResumptionRequestAccepted, default: 0]
        let rejected = deltas[.guardResumptionRejected, default: 0]
        let confirmed = deltas[.guardResumptionConfirmed, default: 0]
        let timedOut = deltas[.guardResumptionTimedOut, default: 0]
        let resolutionMismatch = deltas[.guardResumptionResolutionMismatch, default: 0]
        let activationMismatch = deltas[.guardResumptionActivationMismatch, default: 0]
        let treatmentDisabled = deltas[.guardResumptionTreatmentDisabled, default: 0]
        let failures = rejected + timedOut + activationMismatch

        guard supervisedEligibleAttempts >= 0,
            UInt64(supervisedEligibleAttempts) == eligible
        else {
            invalidReasons.append(.supervisedTallyMismatch)
            return evaluation(
                .invalid,
                invalidReasons,
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }
        guard requestAccepted + rejected == eligible,
            confirmed + timedOut + activationMismatch == requestAccepted
        else {
            invalidReasons.append(.terminalOutcomesIncomplete)
            return evaluation(
                .invalid,
                invalidReasons,
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }
        if !invalidReasons.isEmpty {
            return evaluation(
                .invalid,
                invalidReasons,
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }
        if resolutionMismatch > 0 || activationMismatch > 0 {
            return evaluation(
                .fail,
                [.identityMismatch],
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }
        if treatmentDisabled > 0 {
            return evaluation(
                .fail,
                [.treatmentAlreadyDisabled],
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }
        if failures > 0 {
            return evaluation(
                .fail,
                [.reliabilityFailure],
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }
        if supervisedEligibleAttempts < requiredEligibleAttempts {
            return evaluation(
                .inconclusive,
                [.minimumAttemptsNotReached],
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }
        if supervisedEligibleAttempts > requiredEligibleAttempts {
            return evaluation(
                .invalid,
                [.plannedSampleExceeded],
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }

        let observedReliability = Double(confirmed) / Double(eligible)
        let failureUpperBound = zeroFailureUpperBound(sampleSize: supervisedEligibleAttempts)
        guard observedReliability >= minimumReliability,
            let failureUpperBound,
            failureUpperBound < maximumFailureProportion
        else {
            return evaluation(
                .fail,
                [.reliabilityFailure],
                supervisedEligibleAttempts: supervisedEligibleAttempts,
                eligible: eligible,
                confirmed: confirmed,
                failures: failures
            )
        }

        return evaluation(
            .pass,
            [],
            supervisedEligibleAttempts: supervisedEligibleAttempts,
            eligible: eligible,
            confirmed: confirmed,
            failures: failures
        )
    }

    private static func reportsAreCompatible(
        _ start: FlowmoEvidenceReport,
        _ end: FlowmoEvidenceReport
    ) -> Bool {
        start.schemaVersion == FlowmoEvidenceReport.currentSchemaVersion
            && end.schemaVersion == FlowmoEvidenceReport.currentSchemaVersion
            && start.measurementPlan == .focusGuardResumptionV1
            && end.measurementPlan == .focusGuardResumptionV1
            && start.maximumCountPerCounter == FlowmoEvidenceReport.maximumCountPerCounter
            && end.maximumCountPerCounter == FlowmoEvidenceReport.maximumCountPerCounter
            && start.maximumPendingRecords == FlowmoEvidenceReport.maximumPendingRecords
            && end.maximumPendingRecords == FlowmoEvidenceReport.maximumPendingRecords
            && start.limitations == FlowmoEvidenceReport.Limitation.allCases
            && end.limitations == FlowmoEvidenceReport.Limitation.allCases
    }

    private static func validatedCounts(
        _ report: FlowmoEvidenceReport
    ) -> [EvidenceSignal: UInt64]? {
        guard report.counters.count == EvidenceSignal.allCases.count else { return nil }
        var counts: [EvidenceSignal: UInt64] = [:]
        for counter in report.counters {
            guard counts[counter.signal] == nil,
                counter.count <= FlowmoEvidenceReport.maximumCountPerCounter
            else { return nil }
            counts[counter.signal] = counter.count
        }
        guard counts.count == EvidenceSignal.allCases.count else { return nil }
        let openChosen = counts[.guardOpenOnceChosen, default: 0]
        let openTerminal =
            counts[.guardOpenOnceActivationAccepted, default: 0]
            + counts[.guardOpenOnceNotAccepted, default: 0]
        let stayChosen = counts[.guardStayFocusedChosen, default: 0]
        let stayClassified =
            counts[.guardResumptionEligible, default: 0]
            + counts[.guardResumptionIneligible, default: 0]
            + counts[.guardResumptionTreatmentDisabled, default: 0]
        let eligible = counts[.guardResumptionEligible, default: 0]
        let eligibleClassified =
            counts[.guardResumptionRequestAccepted, default: 0]
            + counts[.guardResumptionRejected, default: 0]
        let requestAccepted = counts[.guardResumptionRequestAccepted, default: 0]
        let requestTerminal =
            counts[.guardResumptionConfirmed, default: 0]
            + counts[.guardResumptionTimedOut, default: 0]
            + counts[.guardResumptionActivationMismatch, default: 0]
        guard openChosen == openTerminal,
            stayChosen == stayClassified,
            eligible == eligibleClassified,
            requestTerminal <= requestAccepted,
            counts[.guardResumptionResolutionMismatch, default: 0]
                <= counts[.guardResumptionIneligible, default: 0]
        else { return nil }
        return counts
    }

    private static func evaluation(
        _ decision: Decision,
        _ reasons: [Reason],
        supervisedEligibleAttempts: Int,
        eligible: UInt64 = 0,
        confirmed: UInt64 = 0,
        failures: UInt64 = 0
    ) -> Evaluation {
        let upperBound =
            failures == 0
            ? zeroFailureUpperBound(sampleSize: supervisedEligibleAttempts)
            : nil
        return Evaluation(
            decision: decision,
            reasons: reasons,
            supervisedEligibleAttempts: supervisedEligibleAttempts,
            recordedEligibleAttempts: eligible,
            confirmedAttempts: confirmed,
            recordedFailures: failures,
            oneSidedFailureUpperBound: upperBound
        )
    }

    private static func zeroFailureUpperBound(sampleSize: Int) -> Double? {
        guard sampleSize > 0 else { return nil }
        return 1 - pow(1 - confidenceLevel, 1 / Double(sampleSize))
    }
}
