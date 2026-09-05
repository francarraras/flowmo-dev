import FlowmoCore
import FlowmoSync
import Foundation
import XCTest

@testable import FlowmoPhone

@MainActor
final class PhoneLocalStoreTests: XCTestCase {
    func testLocalOnlyActionsDoNotCreateSyncMetadata() throws {
        try withRoot { root in
            let store = Store(root: root)
            let controller = PhoneSessionController(
                store: store,
                mode: .localOnly,
                attention: PhoneAttention(notificationsEnabled: false)
            )
            controller.intentionDraft = "local synthetic proof"
            controller.start()

            XCTAssertEqual(try store.load().live?.phase, .prime)
            controller.startRunning()
            controller.becameActive()
            controller.skip()
            controller.stopFocus()
            controller.skip()
            controller.skip()
            controller.dismissCloseBeat()

            XCTAssertEqual(try store.load().history.count, 1)
            XCTAssertNil(controller.activeIssue)
            XCTAssertEqual(controller.syncStatus.phase, .localOnly)
            XCTAssertNil(controller.syncStatus.issueCode)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("sync").path))

            controller.deleteAllData()

            XCTAssertEqual(try store.load(), .empty)
            XCTAssertEqual(controller.userNotice, "All local Flowmo data was deleted.")
            XCTAssertNil(controller.activeIssue)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("sync").path))
        }
    }

    func testLocalContainerDoesNotQueryOrMigrateSharedData() throws {
        try withRoot { root in
            let support = root.appendingPathComponent("app-support")
            let shared = Store(root: root.appendingPathComponent("shared"))
            try shared.save(focusWorld())
            let originalSharedBytes = try Data(contentsOf: shared.worldURL)
            let store = try PhoneSessionController.containerStore(
                mode: .localOnly,
                sharedRoot: {
                    XCTFail("The local edition must not resolve an App Group")
                    return shared.root
                },
                applicationSupport: { support }
            )

            XCTAssertEqual(store.root, support.appendingPathComponent("flowmo", isDirectory: true))
            XCTAssertEqual(try store.load(), .empty)
            XCTAssertEqual(try Data(contentsOf: shared.worldURL), originalSharedBytes)
        }
    }

    func testSharedBootstrapStillFailsClosedWhenAppGroupIsMissing() throws {
        try withRoot { root in
            let legacy = Store(root: root.appendingPathComponent("flowmo"))
            try legacy.save(focusWorld())
            let original = try Data(contentsOf: legacy.worldURL)
            let bootstrap = PhoneStoreBootstrap(
                mode: .sharedWithWidget,
                storeProvider: {
                    try PhoneSessionController.containerStore(
                        mode: .sharedWithWidget,
                        sharedRoot: { nil },
                        applicationSupport: {
                            XCTFail("Missing App Group must not fall back to local storage")
                            return root
                        }
                    )
                },
                attention: PhoneAttention(notificationsEnabled: false)
            )

            XCTAssertNil(bootstrap.controller)
            bootstrap.retry()
            XCTAssertNil(bootstrap.controller)
            XCTAssertEqual(try Data(contentsOf: legacy.worldURL), original)
        }
    }

    func testLocalContainerFailsClosedWhenApplicationSupportIsMissing() throws {
        try withRoot { root in
            XCTAssertThrowsError(
                try PhoneSessionController.containerStore(
                    mode: .localOnly,
                    sharedRoot: {
                        XCTFail("Missing local storage must not fall back to shared storage")
                        return root
                    },
                    applicationSupport: { nil }
                )
            ) { error in
                guard case PhoneStoreConfigurationError.missingApplicationSupport = error else {
                    return XCTFail("Unexpected failure: \(type(of: error))")
                }
            }
        }
    }

    func testLocalBootstrapPreservesUnreadableWorldInsteadOfReplacingStore() throws {
        try withRoot { root in
            let store = Store(root: root)
            let original = Data("unreadable synthetic local world".utf8)
            try original.write(to: store.worldURL)
            let bootstrap = PhoneStoreBootstrap(
                mode: .localOnly,
                storeProvider: { store },
                attention: PhoneAttention(notificationsEnabled: false)
            )
            var controller = try XCTUnwrap(bootstrap.controller)
            XCTAssertTrue(controller.isLocalOnly)
            XCTAssertTrue(controller.storeNeedsRecovery)
            controller.intentionDraft = "must remain blocked"
            controller.start()
            XCTAssertEqual(try Data(contentsOf: store.worldURL), original)

            bootstrap.retry()

            controller = try XCTUnwrap(bootstrap.controller)
            XCTAssertTrue(controller.storeNeedsRecovery)
            XCTAssertEqual(controller.store.root, root)
            XCTAssertEqual(try Data(contentsOf: store.worldURL), original)
        }
    }

    func testSharedContainerRetainsLegacyMigrationAndInvalidStoreRecovery() throws {
        try withRoot { root in
            let support = root.appendingPathComponent("support")
            let legacy = Store(root: support.appendingPathComponent("flowmo"))
            let shared = Store(root: root.appendingPathComponent("shared"))
            try legacy.save(focusWorld())
            let migrated = try PhoneSessionController.containerStore(
                mode: .sharedWithWidget,
                sharedRoot: { shared.root },
                applicationSupport: { support }
            )
            XCTAssertEqual(migrated.root, shared.root)
            XCTAssertEqual(try migrated.load(), try legacy.load())

            let invalid = Data("invalid synthetic shared world".utf8)
            try invalid.write(to: shared.worldURL)
            try invalid.write(to: legacy.worldURL)
            let blockedStore = try PhoneSessionController.containerStore(
                mode: .sharedWithWidget,
                sharedRoot: { shared.root },
                applicationSupport: { support }
            )
            let controller = PhoneSessionController(
                store: blockedStore,
                attention: PhoneAttention(notificationsEnabled: false)
            )
            XCTAssertFalse(controller.isLocalOnly)
            XCTAssertTrue(controller.storeNeedsRecovery)
            XCTAssertEqual(controller.store.root, shared.root)
            XCTAssertEqual(try Data(contentsOf: shared.worldURL), invalid)
        }
    }

    func testLocalRecoveryNeverTrustsRemoteOwnershipMetadata() throws {
        try withRoot { root in
            let store = Store(root: root)
            let world = try focusWorld()
            let generation = UUID()
            try store.save(world)
            try WorldSyncMetadataStore(root: root).save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: world.live?.id,
                    base: WorldSyncSnapshot(world: world, generation: generation)
                )
            )
            let controller = PhoneSessionController(
                store: store,
                mode: .localOnly,
                attention: PhoneAttention(notificationsEnabled: false)
            )
            XCTAssertTrue(try XCTUnwrap(controller.world.live).isPaused)

            try store.save(world)
            controller.retryStore()

            XCTAssertTrue(try XCTUnwrap(controller.world.live).isPaused)
            XCTAssertFalse(controller.storeNeedsRecovery)
        }
    }

    private func focusWorld() throws -> World {
        var engine = Engine()
        let now = Date().addingTimeInterval(-120)
        try engine.apply(.start(intention: "synthetic container proof"), now: now)
        try engine.apply(.skip, now: now)
        return engine.world
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-phone-local-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
