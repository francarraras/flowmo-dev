import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoWindow

@MainActor
final class FocusGuardEvidenceAdapterTests: XCTestCase {
    private final class FakeApplication: FocusGuardApplication {
        let focusGuardProcessIdentity: FocusGuardProcessIdentity?
        var focusGuardIsHidden = false
        var activationAccepted = true
        var activationCount = 0

        init(identity: FocusGuardProcessIdentity) {
            self.focusGuardProcessIdentity = identity
        }

        func focusGuardHide() -> Bool {
            focusGuardIsHidden = true
            return true
        }

        func focusGuardUnhide() -> Bool {
            focusGuardIsHidden = false
            return true
        }

        func focusGuardActivate() -> Bool {
            activationCount += 1
            return activationAccepted
        }
    }

    private let identity = FocusGuardProcessIdentity(
        processIdentifier: 42,
        bundleIdentifier: "app.flowmo.tests.guarded",
        launchDate: Date(timeIntervalSince1970: 1_800_000_000)
    )

    func testPromptStayAndAcceptedOpenEmitExactSemanticEventsOnce() throws {
        let application = FakeApplication(identity: identity)
        let adapter = FocusGuardAdapter { identity in
            identity == self.identity ? application : nil
        }
        var events: [FocusGuardEvidenceEvent] = []
        var bringForwardCount = 0
        adapter.attach(
            bringForward: { bringForwardCount += 1 },
            observeEvidence: { events.append($0) }
        )
        adapter.reconcile(world: try guardedFocusWorld())
        defer { adapter.reconcile(world: .empty) }

        adapter.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        XCTAssertEqual(events, [.promptOfferedAfterConfirmedHide])
        XCTAssertEqual(bringForwardCount, 1)
        XCTAssertNotNil(adapter.runtime.interception)

        adapter.stayFocused()
        adapter.stayFocused()
        XCTAssertEqual(
            events,
            [.promptOfferedAfterConfirmedHide, .stayFocusedResumptionIneligible]
        )
        XCTAssertNil(adapter.runtime.interception)

        adapter.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        adapter.openOnce()
        adapter.openOnce()
        XCTAssertEqual(
            events,
            [
                .promptOfferedAfterConfirmedHide,
                .stayFocusedResumptionIneligible,
                .promptOfferedAfterConfirmedHide,
                .openOnceActivationAccepted,
            ]
        )
        XCTAssertFalse(adapter.runtime.degraded)
    }

    func testFailureEventsDistinguishPrePromptFromOpenNotAccepted() throws {
        var prePromptEvents: [FocusGuardEvidenceEvent] = []
        let unavailable = FocusGuardAdapter { _ in nil }
        unavailable.attach(
            bringForward: {},
            observeEvidence: { prePromptEvents.append($0) }
        )
        unavailable.reconcile(world: try guardedFocusWorld())
        defer { unavailable.reconcile(world: .empty) }

        unavailable.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        XCTAssertEqual(prePromptEvents, [.interceptionFailedBeforePrompt])
        XCTAssertTrue(unavailable.runtime.degraded)
        XCTAssertNil(unavailable.runtime.interception)

        let application = FakeApplication(identity: identity)
        application.activationAccepted = false
        var openEvents: [FocusGuardEvidenceEvent] = []
        let rejected = FocusGuardAdapter { identity in
            identity == self.identity ? application : nil
        }
        rejected.attach(
            bringForward: {},
            observeEvidence: { openEvents.append($0) }
        )
        rejected.reconcile(world: try guardedFocusWorld())
        defer { rejected.reconcile(world: .empty) }

        rejected.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        rejected.openOnce()
        XCTAssertEqual(
            openEvents,
            [.promptOfferedAfterConfirmedHide, .openOnceNotAccepted]
        )
        XCTAssertTrue(rejected.runtime.degraded)
        XCTAssertNil(rejected.runtime.allowedProcessIdentity)
    }

    func testIdleActionsEmitNoEvidence() {
        let adapter = FocusGuardAdapter { _ in nil }
        var events: [FocusGuardEvidenceEvent] = []
        adapter.attach(
            bringForward: {},
            observeEvidence: { events.append($0) }
        )

        adapter.stayFocused()
        adapter.openOnce()

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(adapter.runtime, FocusGuardRuntime())
    }

    func testStayFocusedReactivatesExactPriorProcessAndRequiresMatchingNotification() throws {
        let priorIdentity = FocusGuardProcessIdentity(
            processIdentifier: 7,
            bundleIdentifier: "app.flowmo.tests.work",
            launchDate: identity.launchDate
        )
        let guardedApplication = FakeApplication(identity: identity)
        let priorApplication = FakeApplication(identity: priorIdentity)
        let adapter = FocusGuardAdapter { requested in
            switch requested {
            case self.identity: guardedApplication
            case priorIdentity: priorApplication
            default: nil
            }
        }
        var events: [FocusGuardEvidenceEvent] = []
        adapter.attach(bringForward: {}, observeEvidence: { events.append($0) })
        adapter.reconcile(world: try guardedFocusWorld())
        defer { adapter.reconcile(world: .empty) }

        adapter.handleActivation(
            processIdentity: priorIdentity,
            displayName: "Work",
            isSelf: false
        )
        adapter.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        adapter.stayFocused()

        XCTAssertEqual(priorApplication.activationCount, 1)
        XCTAssertNil(adapter.runtime.interception)
        XCTAssertNil(adapter.runtime.allowedProcessIdentity)
        XCTAssertEqual(
            events,
            [.promptOfferedAfterConfirmedHide, .stayFocusedResumptionAttemptAccepted]
        )

        adapter.handleActivation(
            processIdentity: priorIdentity,
            displayName: "Work",
            isSelf: false
        )
        XCTAssertEqual(events.last, .resumptionConfirmed)
        XCTAssertTrue(adapter.resumptionTreatmentEnabled)
    }

    func testStayFocusedClassifiesMissingPriorIdentityAndActivationRejection() throws {
        let guardedApplication = FakeApplication(identity: identity)
        let adapter = FocusGuardAdapter { requested in
            requested == self.identity ? guardedApplication : nil
        }
        var events: [FocusGuardEvidenceEvent] = []
        adapter.attach(bringForward: {}, observeEvidence: { events.append($0) })
        adapter.reconcile(world: try guardedFocusWorld())
        defer { adapter.reconcile(world: .empty) }

        adapter.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        adapter.stayFocused()
        XCTAssertEqual(events.last, .stayFocusedResumptionIneligible)

        let priorIdentity = FocusGuardProcessIdentity(
            processIdentifier: 7,
            bundleIdentifier: "app.flowmo.tests.work",
            launchDate: identity.launchDate
        )
        let rejectingApplication = FakeApplication(identity: priorIdentity)
        rejectingApplication.activationAccepted = false
        let rejecting = FocusGuardAdapter { requested in
            switch requested {
            case self.identity: guardedApplication
            case priorIdentity: rejectingApplication
            default: nil
            }
        }
        var rejectingEvents: [FocusGuardEvidenceEvent] = []
        rejecting.attach(bringForward: {}, observeEvidence: { rejectingEvents.append($0) })
        rejecting.reconcile(world: try guardedFocusWorld())
        defer { rejecting.reconcile(world: .empty) }
        rejecting.handleActivation(
            processIdentity: priorIdentity,
            displayName: "Work",
            isSelf: false
        )
        rejecting.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        rejecting.stayFocused()

        XCTAssertEqual(rejectingEvents.last, .stayFocusedResumptionRejected)
        XCTAssertTrue(rejecting.resumptionTreatmentEnabled)
        XCTAssertNil(rejecting.runtime.allowedProcessIdentity)
    }

    func testIdentityMismatchRollsBackTreatmentAndTimeoutKeepsBaselineSafe() throws {
        let priorIdentity = FocusGuardProcessIdentity(
            processIdentifier: 7,
            bundleIdentifier: "app.flowmo.tests.work",
            launchDate: identity.launchDate
        )
        let reusedIdentity = FocusGuardProcessIdentity(
            processIdentifier: priorIdentity.processIdentifier,
            bundleIdentifier: priorIdentity.bundleIdentifier,
            launchDate: priorIdentity.launchDate.addingTimeInterval(1)
        )
        let guardedApplication = FakeApplication(identity: identity)
        let reusedApplication = FakeApplication(identity: reusedIdentity)
        let mismatch = FocusGuardAdapter { requested in
            requested == self.identity ? guardedApplication : reusedApplication
        }
        var mismatchEvents: [FocusGuardEvidenceEvent] = []
        mismatch.attach(bringForward: {}, observeEvidence: { mismatchEvents.append($0) })
        mismatch.reconcile(world: try guardedFocusWorld())
        defer { mismatch.reconcile(world: .empty) }
        mismatch.handleActivation(
            processIdentity: priorIdentity,
            displayName: "Work",
            isSelf: false
        )
        mismatch.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        mismatch.stayFocused()

        XCTAssertEqual(mismatchEvents.last, .stayFocusedResumptionResolutionMismatch)
        XCTAssertFalse(mismatch.resumptionTreatmentEnabled)
        XCTAssertEqual(reusedApplication.activationCount, 0)
        mismatch.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        mismatch.stayFocused()
        XCTAssertEqual(mismatchEvents.last, .stayFocusedResumptionTreatmentDisabled)
        XCTAssertEqual(reusedApplication.activationCount, 0)

        let priorApplication = FakeApplication(identity: priorIdentity)
        let timeout = FocusGuardAdapter { requested in
            switch requested {
            case self.identity: guardedApplication
            case priorIdentity: priorApplication
            default: nil
            }
        }
        var timeoutEvents: [FocusGuardEvidenceEvent] = []
        timeout.attach(bringForward: {}, observeEvidence: { timeoutEvents.append($0) })
        timeout.reconcile(world: try guardedFocusWorld())
        defer { timeout.reconcile(world: .empty) }
        timeout.handleActivation(
            processIdentity: priorIdentity,
            displayName: "Work",
            isSelf: false
        )
        timeout.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        timeout.stayFocused()
        timeout.expirePendingResumptionForTesting()

        XCTAssertEqual(timeoutEvents.last, .resumptionTimedOut)
        XCTAssertTrue(timeout.resumptionTreatmentEnabled)
        XCTAssertNil(timeout.runtime.allowedProcessIdentity)
    }

    func testDifferentActivationAfterAcceptedRequestRollsBackTreatment() throws {
        let priorIdentity = FocusGuardProcessIdentity(
            processIdentifier: 7,
            bundleIdentifier: "app.flowmo.tests.work",
            launchDate: identity.launchDate
        )
        let otherIdentity = FocusGuardProcessIdentity(
            processIdentifier: 8,
            bundleIdentifier: "app.flowmo.tests.other",
            launchDate: identity.launchDate
        )
        let guardedApplication = FakeApplication(identity: identity)
        let priorApplication = FakeApplication(identity: priorIdentity)
        let adapter = FocusGuardAdapter { requested in
            switch requested {
            case self.identity: guardedApplication
            case priorIdentity: priorApplication
            default: nil
            }
        }
        var events: [FocusGuardEvidenceEvent] = []
        adapter.attach(bringForward: {}, observeEvidence: { events.append($0) })
        adapter.reconcile(world: try guardedFocusWorld())
        defer { adapter.reconcile(world: .empty) }
        adapter.handleActivation(
            processIdentity: priorIdentity,
            displayName: "Work",
            isSelf: false
        )
        adapter.handleActivation(
            processIdentity: identity,
            displayName: "Guarded",
            isSelf: false
        )
        adapter.stayFocused()
        adapter.handleActivation(
            processIdentity: otherIdentity,
            displayName: "Other",
            isSelf: false
        )

        XCTAssertEqual(events.last, .resumptionActivationMismatch)
        XCTAssertFalse(adapter.resumptionTreatmentEnabled)
        XCTAssertNil(adapter.runtime.allowedProcessIdentity)
    }

    func testSixtyCycleAutomatedPipelinePassesWithoutCalendarWait() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-wp3-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let evidence = LocalEvidence(root: root)
        let startTime = Date(timeIntervalSince1970: 1_800_000_000)
        let start = try JSONDecoder.flowmo.decode(
            FlowmoEvidenceReport.self,
            from: evidence.export(generatedAt: startTime)
        )
        let priorIdentity = FocusGuardProcessIdentity(
            processIdentifier: 7,
            bundleIdentifier: "app.flowmo.tests.work",
            launchDate: identity.launchDate
        )
        let guardedApplication = FakeApplication(identity: identity)
        let priorApplication = FakeApplication(identity: priorIdentity)
        let adapter = FocusGuardAdapter { requested in
            switch requested {
            case self.identity: guardedApplication
            case priorIdentity: priorApplication
            default: nil
            }
        }
        var recordResults: [EvidenceRecordResult] = []
        adapter.attach(
            bringForward: {},
            observeEvidence: { event in
                recordResults.append(evidence.record(event))
            }
        )
        adapter.reconcile(world: try guardedFocusWorld())
        defer { adapter.reconcile(world: .empty) }

        for _ in 0..<FocusGuardResumptionGate.requiredEligibleAttempts {
            adapter.handleActivation(
                processIdentity: priorIdentity,
                displayName: "Work",
                isSelf: false
            )
            adapter.handleActivation(
                processIdentity: identity,
                displayName: "Guarded",
                isSelf: false
            )
            adapter.stayFocused()
            adapter.handleActivation(
                processIdentity: priorIdentity,
                displayName: "Work",
                isSelf: false
            )
        }

        XCTAssertEqual(priorApplication.activationCount, 60)
        XCTAssertEqual(recordResults.count, 180)
        XCTAssertTrue(recordResults.allSatisfy { $0 == .recorded })

        let end = try JSONDecoder.flowmo.decode(
            FlowmoEvidenceReport.self,
            from: evidence.export(generatedAt: startTime.addingTimeInterval(2))
        )
        let result = FocusGuardResumptionGate.evaluate(
            start: start,
            end: end,
            supervisedEligibleAttempts: 60,
            firstEligibleAttemptAt: startTime.addingTimeInterval(1),
            integrityIncident: false
        )

        XCTAssertEqual(result.decision, .pass)
        XCTAssertEqual(result.recordedEligibleAttempts, 60)
        XCTAssertEqual(result.confirmedAttempts, 60)
        XCTAssertEqual(result.recordedFailures, 0)
    }

    private func guardedFocusWorld() throws -> World {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var engine = Engine()
        try engine.apply(.start(intention: "test"), now: startedAt)
        try engine.apply(.skip, now: startedAt)
        engine.world.config.focusGuard = FocusGuardConfiguration(
            enabled: true,
            bundleIdentifiers: [identity.bundleIdentifier]
        )
        return engine.world
    }
}
