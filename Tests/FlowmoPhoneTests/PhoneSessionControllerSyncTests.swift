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
            try store.save(world)
            try WorldSyncMetadataStore(root: store.root).save(
                WorldSyncMetadata(remoteLiveSessionID: sessionID)
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

    private func focusWorld(at date: Date) throws -> World {
        var engine = Engine()
        try engine.apply(.start(intention: "phone sync recovery proof"), now: date)
        try engine.apply(.skip, now: date)
        return engine.world
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-phone-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }
}
