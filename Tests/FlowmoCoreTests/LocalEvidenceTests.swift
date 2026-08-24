import Darwin
import Foundation
import XCTest

@testable import FlowmoCore

final class LocalEvidenceTests: XCTestCase {
    func testMissingFileExportsFixedZeroInclusiveReport() throws {
        try withEvidence { evidence, root in
            let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
            let report = try decodeReport(evidence.export(generatedAt: generatedAt))

            XCTAssertEqual(report.schemaVersion, FlowmoEvidenceReport.currentSchemaVersion)
            XCTAssertEqual(report.generatedAt, generatedAt)
            XCTAssertEqual(report.measurementPlan, .focusGuardResumptionV1)
            XCTAssertEqual(
                report.maximumCountPerCounter,
                FlowmoEvidenceReport.maximumCountPerCounter
            )
            XCTAssertEqual(
                report.maximumPendingRecords,
                FlowmoEvidenceReport.maximumPendingRecords
            )
            XCTAssertEqual(report.counters.map(\.signal), EvidenceSignal.allCases)
            XCTAssertEqual(report.counters.map(\.count), Array(repeating: 0, count: EvidenceSignal.allCases.count))
            XCTAssertEqual(report.limitations, FlowmoEvidenceReport.Limitation.allCases)

            let encoded = String(decoding: try evidence.export(generatedAt: generatedAt), as: UTF8.self)
            XCTAssertFalse(encoded.contains(root.path))
            XCTAssertFalse(encoded.contains("private intention"))
            XCTAssertFalse(encoded.contains("com.example.guard"))
            XCTAssertFalse(encoded.contains("11111111-1111-1111-1111-111111111111"))
        }
    }

    func testRecordAggregatesTypedEventsAndKeepsOpenOutcomeAtomic() throws {
        try withEvidence { evidence, root in
            XCTAssertEqual(evidence.record(.promptOfferedAfterConfirmedHide), .recorded)
            XCTAssertEqual(evidence.record(.promptOfferedAfterConfirmedHide), .recorded)
            XCTAssertEqual(evidence.record(.stayFocusedResumptionIneligible), .recorded)
            XCTAssertEqual(evidence.record(.stayFocusedResumptionAttemptAccepted), .recorded)
            XCTAssertEqual(evidence.record(.resumptionConfirmed), .recorded)
            XCTAssertEqual(evidence.record(.openOnceActivationAccepted), .recorded)
            XCTAssertEqual(evidence.record(.openOnceNotAccepted), .recorded)
            XCTAssertEqual(evidence.record(.interceptionFailedBeforePrompt), .recorded)

            let report = try decodeReport(evidence.export(generatedAt: Date(timeIntervalSince1970: 1)))
            XCTAssertEqual(count(.guardPromptOffered, in: report), 2)
            XCTAssertEqual(count(.guardStayFocusedChosen, in: report), 2)
            XCTAssertEqual(count(.guardResumptionEligible, in: report), 1)
            XCTAssertEqual(count(.guardResumptionIneligible, in: report), 1)
            XCTAssertEqual(count(.guardResumptionRequestAccepted, in: report), 1)
            XCTAssertEqual(count(.guardResumptionConfirmed, in: report), 1)
            XCTAssertEqual(count(.guardOpenOnceChosen, in: report), 2)
            XCTAssertEqual(count(.guardOpenOnceActivationAccepted, in: report), 1)
            XCTAssertEqual(count(.guardOpenOnceNotAccepted, in: report), 1)
            XCTAssertEqual(count(.guardInterceptionFailedBeforePrompt, in: report), 1)

            var info = stat()
            XCTAssertEqual(lstat(root.appendingPathComponent("evidence.json").path, &info), 0)
            XCTAssertEqual(info.st_mode & mode_t(0o777), mode_t(0o600))
        }
    }

    func testResumptionEventsKeepEligibilityAndTerminalOutcomesReconcilable() throws {
        try withEvidence { evidence, root in
            XCTAssertEqual(
                evidence.record(.resumptionConfirmed),
                .dropped(.invalidOrUnsupported)
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent("evidence.json").path
                )
            )

            XCTAssertEqual(
                evidence.record(.stayFocusedResumptionRejected),
                .recorded
            )
            XCTAssertEqual(
                evidence.record(.stayFocusedResumptionResolutionMismatch),
                .recorded
            )
            XCTAssertEqual(
                evidence.record(.stayFocusedResumptionTreatmentDisabled),
                .recorded
            )
            XCTAssertEqual(
                evidence.record(.stayFocusedResumptionAttemptAccepted),
                .recorded
            )
            XCTAssertEqual(evidence.record(.resumptionTimedOut), .recorded)
            XCTAssertEqual(
                evidence.record(.stayFocusedResumptionAttemptAccepted),
                .recorded
            )
            XCTAssertEqual(
                evidence.record(.resumptionActivationMismatch),
                .recorded
            )

            let report = try decodeReport(
                evidence.export(generatedAt: Date(timeIntervalSince1970: 1))
            )
            XCTAssertEqual(count(.guardStayFocusedChosen, in: report), 5)
            XCTAssertEqual(count(.guardResumptionEligible, in: report), 3)
            XCTAssertEqual(count(.guardResumptionIneligible, in: report), 1)
            XCTAssertEqual(count(.guardResumptionTreatmentDisabled, in: report), 1)
            XCTAssertEqual(count(.guardResumptionRequestAccepted, in: report), 2)
            XCTAssertEqual(count(.guardResumptionRejected, in: report), 1)
            XCTAssertEqual(count(.guardResumptionTimedOut, in: report), 1)
            XCTAssertEqual(count(.guardResumptionResolutionMismatch, in: report), 1)
            XCTAssertEqual(count(.guardResumptionActivationMismatch, in: report), 1)
        }
    }

    func testMalformedAndFutureDocumentsArePreserved() throws {
        try withEvidence { evidence, root in
            let url = root.appendingPathComponent("evidence.json")
            let malformed = Data("{not-json".utf8)
            try malformed.write(to: url)

            XCTAssertEqual(
                evidence.record(.promptOfferedAfterConfirmedHide),
                .dropped(.invalidOrUnsupported)
            )
            XCTAssertEqual(try Data(contentsOf: url), malformed)
            XCTAssertThrowsError(try evidence.export(generatedAt: Date()))

            let future = Data(
                #"{"schemaVersion":3,"measurementPlan":"focus_guard_resumption_v1","counters":[]}"#.utf8
            )
            try future.write(to: url)
            XCTAssertEqual(
                evidence.record(.promptOfferedAfterConfirmedHide),
                .dropped(.invalidOrUnsupported)
            )
            XCTAssertEqual(try Data(contentsOf: url), future)
        }
    }

    func testUnknownKeysSignalsDuplicatesOversizedAndImpossibleCountsAreRejected() throws {
        try withEvidence { evidence, root in
            let url = root.appendingPathComponent("evidence.json")
            let invalidDocuments = [
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[],"extra":true}"#,
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"unknown","count":1}]}"#,
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"focus_guard_resumption_v1.prompt_offered_after_confirmed_hide","count":1},{"signal":"focus_guard_resumption_v1.prompt_offered_after_confirmed_hide","count":2}]}"#,
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"focus_guard_resumption_v1.prompt_offered_after_confirmed_hide","count":10000001}]}"#,
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"focus_guard_resumption_v1.open_once_chosen","count":0},{"signal":"focus_guard_resumption_v1.open_once_activation_accepted","count":1}]}"#,
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"focus_guard_resumption_v1.open_once_chosen","count":2},{"signal":"focus_guard_resumption_v1.open_once_activation_accepted","count":1}]}"#,
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"focus_guard_resumption_v1.open_once_chosen","count":1},{"signal":"focus_guard_resumption_v1.open_once_activation_accepted","count":1},{"signal":"focus_guard_resumption_v1.open_once_not_accepted","count":1}]}"#,
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"focus_guard_resumption_v1.open_once_chosen","count":10000000},{"signal":"focus_guard_resumption_v1.open_once_activation_accepted","count":9999999}]}"#,
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_instrumentation_v1","counters":[]}"#,
            ]

            for document in invalidDocuments {
                let bytes = Data(document.utf8)
                try bytes.write(to: url)
                XCTAssertEqual(
                    evidence.record(.promptOfferedAfterConfirmedHide),
                    .dropped(.invalidOrUnsupported),
                    document
                )
                XCTAssertThrowsError(
                    try evidence.export(generatedAt: Date(timeIntervalSince1970: 1)),
                    document
                )
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
        }
    }

    func testSaturatedOpenCountsAcceptCensoredTerminalTotals() throws {
        try withEvidence { evidence, root in
            let url = root.appendingPathComponent("evidence.json")
            try Data(
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"focus_guard_resumption_v1.open_once_chosen","count":10000000},{"signal":"focus_guard_resumption_v1.open_once_activation_accepted","count":10000000},{"signal":"focus_guard_resumption_v1.open_once_not_accepted","count":10000000}]}"#
                    .utf8
            ).write(to: url)

            let report = try decodeReport(
                evidence.export(generatedAt: Date(timeIntervalSince1970: 1))
            )
            XCTAssertEqual(
                count(.guardOpenOnceChosen, in: report),
                FlowmoEvidenceReport.maximumCountPerCounter
            )
            XCTAssertEqual(
                count(.guardOpenOnceActivationAccepted, in: report),
                FlowmoEvidenceReport.maximumCountPerCounter
            )
            XCTAssertEqual(
                count(.guardOpenOnceNotAccepted, in: report),
                FlowmoEvidenceReport.maximumCountPerCounter
            )
        }
    }

    func testCounterSaturatesAtTheValidatedMaximum() throws {
        try withEvidence { evidence, root in
            let url = root.appendingPathComponent("evidence.json")
            try Data(
                #"{"schemaVersion":2,"measurementPlan":"focus_guard_resumption_v1","counters":[{"signal":"focus_guard_resumption_v1.prompt_offered_after_confirmed_hide","count":10000000}]}"#
                    .utf8
            ).write(to: url)

            XCTAssertEqual(evidence.record(.promptOfferedAfterConfirmedHide), .recorded)
            let report = try decodeReport(evidence.export(generatedAt: Date(timeIntervalSince1970: 1)))
            XCTAssertEqual(
                count(.guardPromptOffered, in: report),
                FlowmoEvidenceReport.maximumCountPerCounter
            )
        }
    }

    func testSymlinkEvidenceIsPreservedAndNeverFollowsItsTarget() throws {
        try withEvidence { evidence, root in
            let target = root.appendingPathComponent("not-evidence.json")
            let sentinel = Data("do not overwrite".utf8)
            try sentinel.write(to: target)
            let evidenceURL = root.appendingPathComponent("evidence.json")
            try FileManager.default.createSymbolicLink(at: evidenceURL, withDestinationURL: target)

            XCTAssertEqual(
                evidence.record(.promptOfferedAfterConfirmedHide),
                .dropped(.invalidOrUnsupported)
            )
            XCTAssertEqual(try Data(contentsOf: target), sentinel)
            XCTAssertThrowsError(try evidence.export(generatedAt: Date()))

            let deletion = try evidence.deleteOwnedData()
            XCTAssertEqual(deletion.removedArtifactURLs.map(\.lastPathComponent), ["evidence.json"])
            XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        }
    }

    func testRecordDropsImmediatelyWhenLockIsContended() throws {
        try withEvidence { evidence, root in
            let lockURL = root.appendingPathComponent("evidence.lock")
            let fd = open(
                lockURL.path,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                mode_t(S_IRUSR | S_IWUSR)
            )
            XCTAssertGreaterThanOrEqual(fd, 0)
            guard fd >= 0 else { return }
            defer {
                _ = flock(fd, LOCK_UN)
                close(fd)
            }
            XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)

            XCTAssertEqual(evidence.record(.promptOfferedAfterConfirmedHide), .dropped(.busy))
            XCTAssertThrowsError(try evidence.export(generatedAt: Date()))
            XCTAssertThrowsError(try evidence.deleteOwnedData()) { error in
                guard let deletion = error as? LocalEvidenceDeletionError else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertFalse(deletion.remainingArtifactsKnown)
            }
        }
    }

    func testRecorderOrdersPendingWritesBeforeExportAndFlush() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "flowmo-evidence-recorder-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = LocalEvidenceRecorder(root: root)

        recorder.record(.promptOfferedAfterConfirmedHide)
        recorder.record(.openOnceActivationAccepted)
        let first = try decodeReport(recorder.export(generatedAt: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(count(.guardPromptOffered, in: first), 1)
        XCTAssertEqual(count(.guardOpenOnceChosen, in: first), 1)
        XCTAssertEqual(count(.guardOpenOnceActivationAccepted, in: first), 1)

        recorder.record(.stayFocusedResumptionIneligible)
        recorder.flush()
        let second = try decodeReport(
            LocalEvidence(root: root).export(generatedAt: Date(timeIntervalSince1970: 2))
        )
        XCTAssertEqual(count(.guardStayFocusedChosen, in: second), 1)
    }

    func testRecorderSubmissionDoesNotWaitForPersistence() {
        let operationStarted = DispatchSemaphore(value: 0)
        let allowOperationToFinish = DispatchSemaphore(value: 0)
        let recorder = LocalEvidenceRecorder(
            recordOperation: { _ in
                operationStarted.signal()
                allowOperationToFinish.wait()
            },
            exportOperation: { _ in Data() }
        )
        DispatchQueue.global(qos: .userInitiated).async {
            if operationStarted.wait(timeout: .now() + 1) == .success {
                Thread.sleep(forTimeInterval: 0.25)
            }
            allowOperationToFinish.signal()
        }

        let startedAt = Date()
        recorder.record(.stayFocusedResumptionIneligible)
        let submissionDuration = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(submissionDuration, 0.1)
        recorder.flush()
    }

    func testRecorderBoundsOutstandingPersistenceWorkUnderFlood() {
        let operationStarted = DispatchSemaphore(value: 0)
        let allowOperationToFinish = DispatchSemaphore(value: 0)
        let invocationCount = LockedCounter()
        let recorder = LocalEvidenceRecorder(
            recordOperation: { _ in
                if invocationCount.increment() == 1 {
                    operationStarted.signal()
                    allowOperationToFinish.wait()
                }
            },
            exportOperation: { _ in Data() }
        )

        recorder.record(.stayFocusedResumptionIneligible)
        XCTAssertEqual(operationStarted.wait(timeout: .now() + 1), .success)
        for _ in 0..<(FlowmoEvidenceReport.maximumPendingRecords * 100) {
            recorder.record(.promptOfferedAfterConfirmedHide)
        }

        allowOperationToFinish.signal()
        recorder.flush()
        XCTAssertEqual(
            invocationCount.value,
            FlowmoEvidenceReport.maximumPendingRecords
        )

        recorder.record(.stayFocusedResumptionIneligible)
        recorder.flush()
        XCTAssertEqual(
            invocationCount.value,
            FlowmoEvidenceReport.maximumPendingRecords + 1
        )
    }

    func testRecorderFlushBeforeStoreDeletionPreventsEvidenceRecreation() throws {
        try withEvidence { _, root in
            let recorder = LocalEvidenceRecorder(root: root)
            let evidenceURL = root.appendingPathComponent("evidence.json")

            recorder.record(.promptOfferedAfterConfirmedHide)
            recorder.flush()
            XCTAssertTrue(FileManager.default.fileExists(atPath: evidenceURL.path))

            _ = try Store(root: root).deleteAllData()
            recorder.flush()
            XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceURL.path))
        }
    }

    func testStoreDeletionFailsFastWhenEvidenceLockIsHeld() throws {
        try withEvidence { evidence, root in
            XCTAssertEqual(evidence.record(.promptOfferedAfterConfirmedHide), .recorded)
            let fd = open(
                root.appendingPathComponent("evidence.lock").path,
                O_RDWR | O_CLOEXEC | O_NOFOLLOW
            )
            XCTAssertGreaterThanOrEqual(fd, 0)
            guard fd >= 0 else { return }
            defer {
                _ = flock(fd, LOCK_UN)
                close(fd)
            }
            XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)

            XCTAssertThrowsError(try Store(root: root).deleteAllData()) { error in
                guard let deletion = error as? StoreDataDeletionError else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertFalse(deletion.remainingEvidenceArtifactsKnown)
            }
            XCTAssertEqual(try Store(root: root).load(), .empty)
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent("evidence.json").path
                )
            )
        }
    }

    func testDeleteRemovesOnlyExactOwnedArtifactsAndNeverRecurses() throws {
        try withEvidence { evidence, root in
            XCTAssertEqual(evidence.record(.promptOfferedAfterConfirmedHide), .recorded)
            let exactTemporary = root.appendingPathComponent(".evidence.write-\(UUID().uuidString).tmp")
            let similar = root.appendingPathComponent(".evidence.write-not-a-uuid.tmp")
            let exactDirectory = root.appendingPathComponent(".evidence.write-\(UUID().uuidString).tmp")
            let child = exactDirectory.appendingPathComponent("keep.txt")
            try Data("remove".utf8).write(to: exactTemporary)
            try Data("keep".utf8).write(to: similar)
            try FileManager.default.createDirectory(at: exactDirectory, withIntermediateDirectories: true)
            try Data("keep child".utf8).write(to: child)

            XCTAssertThrowsError(try evidence.deleteOwnedData()) { error in
                guard let deletion = error as? LocalEvidenceDeletionError else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertTrue(deletion.remainingArtifactsKnown)
                XCTAssertEqual(
                    deletion.remainingArtifactURLs.map(\.lastPathComponent), [exactDirectory.lastPathComponent])
                XCTAssertEqual(
                    Set(deletion.removedArtifactURLs.map(\.lastPathComponent)),
                    Set(["evidence.json", exactTemporary.lastPathComponent])
                )
            }

            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("evidence.json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: exactTemporary.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: similar.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
        }
    }

    func testEvidenceFailureCannotChangeWorldPersistence() throws {
        try withEvidence { evidence, root in
            let store = Store(root: root)
            var world = World.empty
            world.profile.lastIntention = "private intention"
            try store.save(world)
            let evidenceURL = root.appendingPathComponent("evidence.json")
            try Data("corrupt evidence".utf8).write(to: evidenceURL)

            XCTAssertEqual(
                evidence.record(.promptOfferedAfterConfirmedHide),
                .dropped(.invalidOrUnsupported)
            )
            XCTAssertEqual(try store.load(), world)
        }
    }

    private func withEvidence(_ body: (LocalEvidence, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "flowmo-local-evidence-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(LocalEvidence(root: root), root)
    }

    private func decodeReport(_ data: Data) throws -> FlowmoEvidenceReport {
        try JSONDecoder.flowmo.decode(FlowmoEvidenceReport.self, from: data)
    }

    private func count(_ signal: EvidenceSignal, in report: FlowmoEvidenceReport) -> UInt64 {
        report.counters.first { $0.signal == signal }?.count ?? 0
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
