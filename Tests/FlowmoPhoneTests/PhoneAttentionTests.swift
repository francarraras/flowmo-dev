import FlowmoCore
import Foundation
import UserNotifications
import XCTest

@testable import FlowmoPhone

@MainActor
final class PhoneAttentionTests: XCTestCase {
    func testInFlightAddCannotSurviveARecoveryCancellation() async throws {
        let client = FakePhoneNotificationClient()
        client.suspendNextAdd = true
        let attention = PhoneAttention(client: client)
        let now = Date()
        var engine = try breakEngine(at: now)
        attention.reconcile(world: engine.world, now: now)
        await client.waitUntilAddIsSuspended()

        try engine.apply(.pauseForRecovery, now: now)
        attention.reconcile(world: engine.world, now: now)
        // Model a notification service that finishes an accepted add even after Task.cancel().
        client.resumeAdd()
        await attention.waitForPendingReconciliation()

        XCTAssertEqual(client.added.map(\.identifier), ["flowmo.timed-phase.recall"])
        XCTAssertTrue(client.pending.isEmpty, "The newer cancellation must remove the late old request")
        XCTAssertEqual(client.cancellations.count, 2)
    }

    func testReplacingBreakWithEarlyReflectionRemovesObsoleteRequestsAndPrivateText() async throws {
        let client = FakePhoneNotificationClient()
        let attention = PhoneAttention(client: client)
        let now = Date()
        var engine = try breakEngine(at: now)
        attention.reconcile(world: engine.world, now: now)
        await attention.waitForPendingReconciliation()
        XCTAssertEqual(Set(client.pending.keys), ["flowmo.timed-phase.recall", "flowmo.timed-phase.closeBeat"])

        try engine.apply(.skip, now: now)
        attention.reconcile(world: engine.world, now: now)
        await attention.waitForPendingReconciliation()

        XCTAssertEqual(Array(client.pending.keys), ["flowmo.timed-phase.closeBeat"])
        for request in client.added {
            XCTAssertNil(request.content.sound)
            XCTAssertTrue(request.content.userInfo.isEmpty)
            XCTAssertFalse(request.content.title.contains("PRIVATE_SYNTHETIC"))
            XCTAssertFalse(request.content.body.contains("PRIVATE_SYNTHETIC"))
        }
        XCTAssertEqual(client.permissionRequests, 0)
    }

    func testDeniedNotificationRequestsLeaveFocusAndCaptureDurableWithoutPromptingAtLaunch() async throws {
        let name = "flowmo-notification-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        let store = Store(root: root)
        var world = World.empty
        world.config.cuesEnabled = false
        try store.save(world)
        let client = FakePhoneNotificationClient()
        client.rejectRequests = true
        let attention = PhoneAttention(client: client)
        let controller = PhoneSessionController(
            store: store, mode: .localOnly, attention: attention, userDefaults: defaults
        )
        controller.startRunning()
        controller.intentionDraft = "PRIVATE_SYNTHETIC_INTENTION"
        controller.start()
        await attention.waitForPendingReconciliation()
        XCTAssertEqual(client.added.count, 1, "Exercise an actual rejected scheduling request")
        XCTAssertEqual(client.permissionRequests, 0)
        controller.requestNotifications()
        XCTAssertEqual(client.permissionRequests, 1)

        controller.skip()
        controller.captureDraft = "PRIVATE_SYNTHETIC_THOUGHT"
        controller.submitCapture()
        await attention.waitForPendingReconciliation()

        XCTAssertEqual(try store.load().live?.phase, .focus)
        XCTAssertEqual(try store.load().live?.captures.count, 1)
        XCTAssertNil(controller.activeIssue)
        XCTAssertTrue(client.pending.isEmpty)
    }

    private func breakEngine(at now: Date) throws -> Engine {
        var world = World.empty
        world.config.cuesEnabled = false
        var engine = Engine(world: world)
        let origin = now.addingTimeInterval(-600)
        try engine.apply(.start(intention: "PRIVATE_SYNTHETIC_INTENTION"), now: origin)
        try engine.apply(.skip, now: origin)
        try engine.apply(.stopFocus, now: now)
        return engine
    }
}

@MainActor
private final class FakePhoneNotificationClient: PhoneNotificationClient {
    var permissionRequests = 0
    var rejectRequests = false
    var suspendNextAdd = false
    var pending: [String: UNNotificationRequest] = [:]
    var added: [UNNotificationRequest] = []
    var cancellations: [[String]] = []
    private var suspendedAdd: CheckedContinuation<Void, Never>?
    private var addWaiter: CheckedContinuation<Void, Never>?

    func requestPermission() { permissionRequests += 1 }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        cancellations.append(identifiers)
        for identifier in identifiers { pending.removeValue(forKey: identifier) }
    }

    func add(_ request: UNNotificationRequest) async throws {
        added.append(request)
        if suspendNextAdd {
            suspendNextAdd = false
            await withCheckedContinuation { continuation in
                suspendedAdd = continuation
                addWaiter?.resume()
                addWaiter = nil
            }
        }
        if rejectRequests { throw CocoaError(.featureUnsupported) }
        pending[request.identifier] = request
    }

    func waitUntilAddIsSuspended() async {
        if suspendedAdd != nil { return }
        await withCheckedContinuation { addWaiter = $0 }
    }

    func resumeAdd() {
        suspendedAdd?.resume()
        suspendedAdd = nil
    }
}
