import FlowmoActivity
import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoPhone

@MainActor
final class PhoneFocusActivityTests: XCTestCase {
    func testRepeatedClockReconciliationDoesNotRequestOrUpdateAgain() async throws {
        try await withSetup { client, coordinator, _, _ in
            let focus = self.focus()
            for _ in 0..<20 {
                coordinator.reconcile(focus, canStart: true)
            }
            await coordinator.waitForPendingReconciliation()
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()

            XCTAssertEqual(client.requests, [focus])
            XCTAssertTrue(client.updates.isEmpty)
            XCTAssertTrue(client.ended.isEmpty)
        }
    }

    func testForegroundAndAuthorizationGateOnlyOptionalActivity() async throws {
        try await withSetup { client, coordinator, _, _ in
            let focus = self.focus()
            coordinator.reconcile(focus, canStart: false)
            await coordinator.waitForPendingReconciliation()
            XCTAssertTrue(client.requests.isEmpty)

            client.applicationIsActive = false
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()
            XCTAssertTrue(client.requests.isEmpty)

            client.applicationIsActive = true
            client.activitiesEnabled = false
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()
            XCTAssertTrue(client.requests.isEmpty)

            client.activitiesEnabled = true
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()
            XCTAssertEqual(client.requests, [focus])

            coordinator.reconcile(focus, canStart: false)
            await coordinator.waitForPendingReconciliation()
            XCTAssertEqual(client.activities.count, 1, "Going Home must leave the glance running")
        }
    }

    func testDismissalIsRespectedAcrossCoordinatorRelaunchForTheSameSession() async throws {
        try await withSetup { client, coordinator, defaults, _ in
            let focus = self.focus()
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()
            client.activities = []

            let relaunched = PhoneFocusActivityCoordinator(client: client, userDefaults: defaults)
            relaunched.reconcile(nil, canStart: false)
            await relaunched.waitForPendingReconciliation()
            relaunched.reconcile(focus, canStart: true)
            await relaunched.waitForPendingReconciliation()
            XCTAssertEqual(client.requests.count, 1)

            let nextSession = self.focus()
            relaunched.reconcile(nextSession, canStart: true)
            await relaunched.waitForPendingReconciliation()
            XCTAssertEqual(client.requests, [focus, nextSession])
        }
    }

    func testCleanupAwaitCannotRecreateFocusAfterStopOrBackgrounding() async throws {
        try await withSetup { client, coordinator, _, _ in
            client.activities = [PhoneFocusActivitySnapshot(id: "old", projection: self.focus())]
            client.suspendNextEnd = true
            coordinator.reconcile(self.focus(), canStart: true)
            await client.waitUntilEndIsSuspended()

            coordinator.reconcile(nil, canStart: false)
            client.resumeEnd()
            await coordinator.waitForPendingReconciliation()

            XCTAssertTrue(client.requests.isEmpty)
            XCTAssertTrue(client.activities.isEmpty)
            XCTAssertEqual(client.ended, ["old"])
        }
    }

    func testSystemEndedActivityIsRemovedWithoutRestartingTheSameFocus() async throws {
        try await withSetup { client, coordinator, _, _ in
            let focus = self.focus()
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()
            client.activities[0].isActive = false

            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()

            XCTAssertEqual(client.requests, [focus])
            XCTAssertEqual(client.ended.count, 1)
            XCTAssertTrue(client.activities.isEmpty)
        }
    }

    func testExistingActivitiesAreAdoptedUpdatedAndDeduplicated() async throws {
        try await withSetup { client, coordinator, _, _ in
            let focus = self.focus()
            let previous = FocusActivityProjection(
                sessionID: focus.sessionID,
                startedAt: focus.startedAt.addingTimeInterval(-30)
            )
            client.activities = [
                PhoneFocusActivitySnapshot(id: "keep", projection: previous),
                PhoneFocusActivitySnapshot(id: "duplicate", projection: previous),
                PhoneFocusActivitySnapshot(id: "stale-session", projection: self.focus()),
            ]
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()

            XCTAssertTrue(client.requests.isEmpty)
            XCTAssertEqual(client.updates, [focus])
            XCTAssertEqual(Set(client.ended), ["duplicate", "stale-session"])
            XCTAssertEqual(client.activities, [PhoneFocusActivitySnapshot(id: "keep", projection: focus)])
        }
    }

    func testAppEndedActivityCanResumeButDeletionForgetsDismissedSession() async throws {
        try await withSetup { client, coordinator, defaults, _ in
            let focus = self.focus()
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()
            coordinator.reconcile(nil, canStart: false)
            await coordinator.waitForPendingReconciliation()
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()
            XCTAssertEqual(client.requests.count, 2, "Recovery cleanup must not count as user dismissal")

            client.activities = []
            coordinator.reconcile(focus, canStart: true)
            await coordinator.waitForPendingReconciliation()
            coordinator.endAndForget()
            await coordinator.waitForPendingReconciliation()
            let ownedKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("FlowmoFocusLiveActivity") }
            XCTAssertTrue(ownedKeys.isEmpty)
        }
    }

    func testRequestFailureDoesNotRetryEveryCaptureOrBlockTheSession() async throws {
        try await withSetup { client, coordinator, defaults, root in
            client.rejectRequests = true
            let store = Store(root: root)
            let controller = PhoneSessionController(
                store: store,
                mode: .localOnly,
                attention: PhoneAttention(notificationsEnabled: false),
                userDefaults: defaults,
                focusActivity: coordinator
            )
            controller.becameActive()
            controller.intentionDraft = "private synthetic intention"
            controller.start()
            controller.skip()
            await coordinator.waitForPendingReconciliation()
            controller.captureDraft = "private synthetic thought"
            controller.submitCapture()
            await coordinator.waitForPendingReconciliation()

            XCTAssertEqual(client.requests.count, 1)
            XCTAssertNil(controller.activeIssue)
            XCTAssertEqual(try store.load().live?.phase, .focus)
            XCTAssertEqual(try store.load().live?.captures.count, 1)
            XCTAssertTrue(client.activities.isEmpty)
        }
    }

    func testLocalControllerEndsStaleClockOnColdRecoveryAndNeverSilentlyResumes() async throws {
        try await withSetup { client, coordinator, defaults, root in
            let store = Store(root: root)
            var engine = Engine()
            let origin = Date().addingTimeInterval(-120)
            try engine.apply(.start(intention: "private synthetic intention"), now: origin)
            try engine.apply(.skip, now: origin)
            try store.save(engine.world)
            let focus = try XCTUnwrap(FocusActivityProjection(world: engine.world))
            client.activities = [PhoneFocusActivitySnapshot(id: "prior-process", projection: focus)]
            let controller = PhoneSessionController(
                store: store,
                mode: .localOnly,
                attention: PhoneAttention(notificationsEnabled: false),
                userDefaults: defaults,
                focusActivity: coordinator
            )
            controller.becameActive()
            await coordinator.waitForPendingReconciliation()

            XCTAssertTrue(try XCTUnwrap(controller.world.live).isPaused)
            XCTAssertTrue(client.activities.isEmpty)
            XCTAssertTrue(client.requests.isEmpty)

            controller.continueSession()
            await coordinator.waitForPendingReconciliation()
            XCTAssertEqual(client.requests.count, 1)
            XCTAssertEqual(client.requests.first?.startedAt, controller.world.live?.focusStartedAt)
            controller.becameInactive()
            await coordinator.waitForPendingReconciliation()
            XCTAssertFalse(try XCTUnwrap(controller.world.live).isPaused)
            XCTAssertEqual(client.activities.count, 1)

            let invalid = Data("invalid synthetic store".utf8)
            try invalid.write(to: store.worldURL)
            controller.retryStore()
            await coordinator.waitForPendingReconciliation()
            XCTAssertTrue(controller.storeNeedsRecovery)
            XCTAssertTrue(client.activities.isEmpty)
            XCTAssertEqual(try Data(contentsOf: store.worldURL), invalid)
        }
    }

    func testSharedEditionNeverStartsLocalFocusActivity() async throws {
        try await withSetup { client, coordinator, defaults, root in
            let controller = PhoneSessionController(
                store: Store(root: root),
                attention: PhoneAttention(notificationsEnabled: false),
                userDefaults: defaults,
                focusActivity: coordinator
            )
            controller.becameActive()
            controller.intentionDraft = "private synthetic intention"
            controller.start()
            controller.skip()
            await coordinator.waitForPendingReconciliation()
            XCTAssertEqual(controller.world.live?.phase, .focus)
            XCTAssertTrue(client.requests.isEmpty)
        }
    }

    private func focus() -> FocusActivityProjection {
        FocusActivityProjection(sessionID: UUID(), startedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func withSetup(
        _ body:
            @MainActor (FakeFocusActivityClient, PhoneFocusActivityCoordinator, UserDefaults, URL) async throws -> Void
    ) async throws {
        let name = "flowmo-focus-activity-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        let client = FakeFocusActivityClient()
        let coordinator = PhoneFocusActivityCoordinator(client: client, userDefaults: defaults)
        try await body(client, coordinator, defaults, root)
    }
}

@MainActor
private final class FakeFocusActivityClient: PhoneFocusActivityClient {
    var activities: [PhoneFocusActivitySnapshot] = []
    var activitiesEnabled = true
    var applicationIsActive = true
    var rejectRequests = false
    var suspendNextEnd = false
    var requests: [FocusActivityProjection] = []
    var updates: [FocusActivityProjection] = []
    var ended: [String] = []
    private var suspendedEnd: CheckedContinuation<Void, Never>?
    private var endWaiter: CheckedContinuation<Void, Never>?

    func request(_ projection: FocusActivityProjection) throws -> PhoneFocusActivitySnapshot {
        requests.append(projection)
        if rejectRequests { throw CocoaError(.featureUnsupported) }
        let activity = PhoneFocusActivitySnapshot(id: UUID().uuidString, projection: projection)
        activities.append(activity)
        return activity
    }

    func update(_ activity: PhoneFocusActivitySnapshot, to projection: FocusActivityProjection) async {
        updates.append(projection)
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = PhoneFocusActivitySnapshot(id: activity.id, projection: projection)
        }
    }

    func end(_ activity: PhoneFocusActivitySnapshot) async {
        if suspendNextEnd {
            suspendNextEnd = false
            await withCheckedContinuation { continuation in
                suspendedEnd = continuation
                endWaiter?.resume()
                endWaiter = nil
            }
        }
        ended.append(activity.id)
        activities.removeAll { $0.id == activity.id }
    }

    func waitUntilEndIsSuspended() async {
        if suspendedEnd != nil { return }
        await withCheckedContinuation { endWaiter = $0 }
    }

    func resumeEnd() {
        suspendedEnd?.resume()
        suspendedEnd = nil
    }
}
