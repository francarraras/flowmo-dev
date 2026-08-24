import Foundation
import XCTest

@testable import FlowmoCore

final class FocusGuardResumptionGateTests: XCTestCase {
    private let startTime = Date(timeIntervalSince1970: 1_800_000_000)

    func testSixtyConfirmedAttemptsPassTheFrozenGate() {
        let result = evaluate(
            endCounts: successfulCounts(60),
            supervisedAttempts: 60
        )

        XCTAssertEqual(result.decision, .pass)
        XCTAssertTrue(result.reasons.isEmpty)
        XCTAssertEqual(result.recordedEligibleAttempts, 60)
        XCTAssertEqual(result.confirmedAttempts, 60)
        XCTAssertEqual(result.recordedFailures, 0)
        XCTAssertNotNil(result.oneSidedFailureUpperBound)
        XCTAssertLessThan(result.oneSidedFailureUpperBound ?? 1, 0.05)
        XCTAssertGreaterThan(result.oneSidedFailureUpperBound ?? 0, 0.048)
    }

    func testAnyRecordedFailureFailsTheFixedSixtyAttemptRun() {
        var timeout = successfulCounts(60)
        timeout[.guardResumptionConfirmed] = 59
        timeout[.guardResumptionTimedOut] = 1
        var result = evaluate(endCounts: timeout, supervisedAttempts: 60)
        XCTAssertEqual(result.decision, .fail)
        XCTAssertEqual(result.reasons, [.reliabilityFailure])
        XCTAssertEqual(result.recordedFailures, 1)

        var rejected = successfulCounts(60)
        rejected[.guardResumptionRequestAccepted] = 59
        rejected[.guardResumptionConfirmed] = 59
        rejected[.guardResumptionRejected] = 1
        result = evaluate(endCounts: rejected, supervisedAttempts: 60)
        XCTAssertEqual(result.decision, .fail)
        XCTAssertEqual(result.reasons, [.reliabilityFailure])
    }

    func testMismatchAndPriorRollbackFailImmediately() {
        let activationMismatch: [EvidenceSignal: UInt64] = [
            .guardStayFocusedChosen: 1,
            .guardResumptionEligible: 1,
            .guardResumptionRequestAccepted: 1,
            .guardResumptionActivationMismatch: 1,
        ]
        var result = evaluate(endCounts: activationMismatch, supervisedAttempts: 1)
        XCTAssertEqual(result.decision, .fail)
        XCTAssertEqual(result.reasons, [.identityMismatch])

        let resolutionMismatch: [EvidenceSignal: UInt64] = [
            .guardStayFocusedChosen: 1,
            .guardResumptionIneligible: 1,
            .guardResumptionResolutionMismatch: 1,
        ]
        result = evaluate(endCounts: resolutionMismatch, supervisedAttempts: 0)
        XCTAssertEqual(result.decision, .fail)
        XCTAssertEqual(result.reasons, [.identityMismatch])

        let disabled: [EvidenceSignal: UInt64] = [
            .guardStayFocusedChosen: 1,
            .guardResumptionTreatmentDisabled: 1,
        ]
        result = evaluate(endCounts: disabled, supervisedAttempts: 0)
        XCTAssertEqual(result.decision, .fail)
        XCTAssertEqual(result.reasons, [.treatmentAlreadyDisabled])
    }

    func testCleanRunBelowMinimumIsInconclusiveAndExcessIsInvalid() {
        var result = evaluate(
            endCounts: successfulCounts(10),
            supervisedAttempts: 10
        )
        XCTAssertEqual(result.decision, .inconclusive)
        XCTAssertEqual(result.reasons, [.minimumAttemptsNotReached])

        result = evaluate(
            endCounts: successfulCounts(61),
            supervisedAttempts: 61
        )
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertEqual(result.reasons, [.plannedSampleExceeded])
    }

    func testTallyTerminalChronologyWindowSaturationAndIntegrityInvalidate() {
        var result = evaluate(
            endCounts: successfulCounts(10),
            supervisedAttempts: 9
        )
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertTrue(result.reasons.contains(.supervisedTallyMismatch))

        let missingTerminal: [EvidenceSignal: UInt64] = [
            .guardStayFocusedChosen: 1,
            .guardResumptionEligible: 1,
            .guardResumptionRequestAccepted: 1,
        ]
        result = evaluate(endCounts: missingTerminal, supervisedAttempts: 1)
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertTrue(result.reasons.contains(.terminalOutcomesIncomplete))

        result = evaluate(
            endCounts: successfulCounts(60),
            supervisedAttempts: 60,
            firstEligibleAttemptAt: startTime
        )
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertEqual(result.reasons, [.invalidSnapshotChronology])

        result = evaluate(
            endCounts: successfulCounts(60),
            supervisedAttempts: 60,
            endTime: startTime.addingTimeInterval(31 * 24 * 60 * 60),
            firstEligibleAttemptAt: startTime.addingTimeInterval(1)
        )
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertTrue(result.reasons.contains(.collectionWindowExceeded))

        var saturated = successfulCounts(60)
        saturated[.guardPromptOffered] = FlowmoEvidenceReport.maximumCountPerCounter
        result = evaluate(endCounts: saturated, supervisedAttempts: 60)
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertTrue(result.reasons.contains(.counterSaturated))

        result = evaluate(
            endCounts: successfulCounts(60),
            supervisedAttempts: 60,
            integrityIncident: true
        )
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertTrue(result.reasons.contains(.integrityIncident))
    }

    func testDecreasedDuplicateAndIncompleteCounterSetsInvalidate() {
        var startCounts = successfulCounts(1)
        var endCounts = successfulCounts(1)
        startCounts[.guardPromptOffered] = 1
        endCounts[.guardPromptOffered] = 0
        var result = FocusGuardResumptionGate.evaluate(
            start: report(at: startTime, counts: startCounts),
            end: report(at: startTime.addingTimeInterval(2), counts: endCounts),
            supervisedEligibleAttempts: 0,
            firstEligibleAttemptAt: startTime.addingTimeInterval(1),
            integrityIncident: false
        )
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertTrue(result.reasons.contains(.counterDecreased))

        let complete = report(at: startTime, counts: [:])
        let duplicate = FlowmoEvidenceReport(
            generatedAt: startTime.addingTimeInterval(2),
            counters: Array(complete.counters.dropLast()) + [complete.counters[0]]
        )
        result = FocusGuardResumptionGate.evaluate(
            start: complete,
            end: duplicate,
            supervisedEligibleAttempts: 0,
            firstEligibleAttemptAt: startTime.addingTimeInterval(1),
            integrityIncident: false
        )
        XCTAssertEqual(result.decision, .invalid)
        XCTAssertTrue(result.reasons.contains(.invalidCounters))
    }

    private func evaluate(
        endCounts: [EvidenceSignal: UInt64],
        supervisedAttempts: Int,
        endTime: Date? = nil,
        firstEligibleAttemptAt: Date? = nil,
        integrityIncident: Bool = false
    ) -> FocusGuardResumptionGate.Evaluation {
        FocusGuardResumptionGate.evaluate(
            start: report(at: startTime, counts: [:]),
            end: report(
                at: endTime ?? startTime.addingTimeInterval(2),
                counts: endCounts
            ),
            supervisedEligibleAttempts: supervisedAttempts,
            firstEligibleAttemptAt: firstEligibleAttemptAt
                ?? startTime.addingTimeInterval(1),
            integrityIncident: integrityIncident
        )
    }

    private func successfulCounts(_ attempts: UInt64) -> [EvidenceSignal: UInt64] {
        [
            .guardStayFocusedChosen: attempts,
            .guardResumptionEligible: attempts,
            .guardResumptionRequestAccepted: attempts,
            .guardResumptionConfirmed: attempts,
        ]
    }

    private func report(
        at generatedAt: Date,
        counts: [EvidenceSignal: UInt64]
    ) -> FlowmoEvidenceReport {
        FlowmoEvidenceReport(
            generatedAt: generatedAt,
            counters: EvidenceSignal.allCases.map { signal in
                FlowmoEvidenceReport.Counter(
                    signal: signal,
                    count: counts[signal, default: 0]
                )
            }
        )
    }
}
