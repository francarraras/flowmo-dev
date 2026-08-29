import FlowmoCore
import FlowmoSync
import Foundation
import XCTest

@testable import FlowmoPhone

@MainActor
final class PhoneSessionControllerSyncTests: XCTestCase {
    func testRemoteLiveSessionIsNotPausedAtPhoneStartup() throws {
        try withStore { store in
            let world = try focusWorld(at: Date().addingTimeInterval(-120))
            let sessionID = try XCTUnwrap(world.live?.id)
            let generation = uuid(1)
            let snapshot = WorldSyncSnapshot(world: world, generation: generation)
            try store.save(world)
            try WorldSyncMetadataStore(root: store.root).save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: sessionID,
                    base: snapshot
                )
            )

            let controller = PhoneSessionController(
                store: store,
                attention: PhoneAttention(notificationsEnabled: false)
            )

            XCTAssertEqual(controller.world.live?.id, sessionID)
            XCTAssertFalse(try XCTUnwrap(controller.world.live).isPaused)
            XCTAssertFalse(controller.storeNeedsRecovery)
        }
    }

    func testLocallyOwnedLiveSessionStillPausesAtPhoneStartup() throws {
        try withStore { store in
            let world = try focusWorld(at: Date().addingTimeInterval(-120))
            try store.save(world)

            let controller = PhoneSessionController(
                store: store,
                attention: PhoneAttention(notificationsEnabled: false)
            )

            XCTAssertTrue(try XCTUnwrap(controller.world.live).isPaused)
            XCTAssertFalse(controller.storeNeedsRecovery)
        }
    }

    func testRemoteOwnershipChangesOnlyAfterAValidLocalMutationPersists() throws {
        try withStore { store in
            let world = try focusWorld(at: Date().addingTimeInterval(-120))
            let sessionID = try XCTUnwrap(world.live?.id)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            let generation = uuid(2)
            try store.save(world)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: sessionID,
                    base: WorldSyncSnapshot(world: world, generation: generation)
                )
            )
            let controller = PhoneSessionController(
                store: store,
                attention: PhoneAttention(notificationsEnabled: false)
            )

            controller.continueSession()

            XCTAssertEqual(try metadataStore.load().remoteLiveSessionID, sessionID)
            XCTAssertEqual(controller.world.live?.phase, .focus)

            controller.stopFocus()

            XCTAssertNil(try metadataStore.load().remoteLiveSessionID)
            XCTAssertEqual(controller.world.live?.phase, .onBreak)
        }
    }

    func testStaleRemoteOwnershipCannotSkipRecoveryAfterLocalWorldChange() throws {
        try withStore { store in
            let remoteWorld = try focusWorld(at: Date().addingTimeInterval(-120))
            let sessionID = try XCTUnwrap(remoteWorld.live?.id)
            let generation = uuid(3)
            try WorldSyncMetadataStore(root: store.root).save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: sessionID,
                    base: WorldSyncSnapshot(world: remoteWorld, generation: generation)
                )
            )

            var locallyChanged = Engine(world: remoteWorld)
            try locallyChanged.apply(.stopFocus, now: Date())
            try store.save(locallyChanged.world)

            let controller = PhoneSessionController(
                store: store,
                attention: PhoneAttention(notificationsEnabled: false)
            )

            XCTAssertEqual(controller.world.live?.phase, .onBreak)
            XCTAssertTrue(try XCTUnwrap(controller.world.live).isPaused)
        }
    }

    func testOwnershipWriteFailureSurfacesWithoutRepeatingDurableAction() throws {
        try withStore { store in
            let remoteWorld = try focusWorld(at: Date().addingTimeInterval(-120))
            let sessionID = try XCTUnwrap(remoteWorld.live?.id)
            let generation = uuid(4)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try store.save(remoteWorld)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: sessionID,
                    base: WorldSyncSnapshot(world: remoteWorld, generation: generation)
                )
            )
            let controller = PhoneSessionController(
                store: store,
                attention: PhoneAttention(notificationsEnabled: false)
            )

            try FileManager.default.removeItem(at: metadataStore.stateURL)
            try FileManager.default.createDirectory(
                at: metadataStore.stateURL,
                withIntermediateDirectories: false
            )

            controller.captureDraft = "one durable thought"
            controller.showCapture = true
            controller.submitCapture()

            XCTAssertEqual(try store.load().live?.captures.map(\.text), ["one durable thought"])
            XCTAssertEqual(controller.world.live?.captures.map(\.text), ["one durable thought"])
            XCTAssertTrue(controller.captureDraft.isEmpty)
            XCTAssertFalse(controller.showCapture)
            XCTAssertEqual(controller.activeIssue?.code, .persistenceFailed)
        }
    }

    func testExactCloseBeatAdoptsDurableCompletionWhenOwnershipWriteFails() throws {
        try withStore { store in
            let world = try closeBeatWorld(at: Date().addingTimeInterval(-120))
            let sessionID = try XCTUnwrap(world.live?.id)
            let generation = uuid(5)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try store.save(world)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: sessionID,
                    base: WorldSyncSnapshot(world: world, generation: generation)
                )
            )
            let controller = PhoneSessionController(
                store: store,
                attention: PhoneAttention(notificationsEnabled: false)
            )
            try FileManager.default.removeItem(at: metadataStore.stateURL)
            try FileManager.default.createDirectory(
                at: metadataStore.stateURL,
                withIntermediateDirectories: false
            )

            controller.dismissCloseBeat()

            XCTAssertNil(controller.world.live)
            XCTAssertNil(try store.load().live)
            XCTAssertEqual(controller.world.history.last?.id, sessionID)
            XCTAssertEqual(controller.intentionDraft, "continue after the authority seam")
            XCTAssertEqual(controller.activeIssue?.code, .syncMetadataUnavailable)
            XCTAssertEqual(controller.activeIssue?.title, "Session saved; sync needs attention")
            XCTAssertEqual(
                controller.activeIssue?.message,
                "Your Session change was saved on this device, but Flowmo couldn’t update its private sync state. Other devices may be temporarily out of date."
            )
            XCTAssertEqual(controller.recentIssues.last?.operation, .sync)
        }
    }

    private func focusWorld(at date: Date) throws -> World {
        var engine = Engine()
        try engine.apply(.start(intention: "phone sync recovery proof"), now: date)
        try engine.apply(.skip, now: date)
        return engine.world
    }

    private func closeBeatWorld(at date: Date) throws -> World {
        var engine = Engine()
        try engine.apply(.start(intention: "phone authority proof"), now: date)
        try engine.apply(.skip, now: date.addingTimeInterval(1))
        try engine.apply(.stopFocus, now: date.addingTimeInterval(60))
        try engine.apply(.skip, now: date.addingTimeInterval(61))
        try engine.apply(
            .setRecallText("continue after the authority seam"),
            now: date.addingTimeInterval(62)
        )
        try engine.apply(.skip, now: date.addingTimeInterval(63))
        return engine.world
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-phone-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
