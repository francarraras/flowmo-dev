import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoPhone

@MainActor
final class PhoneDataRecoveryTests: XCTestCase {
    func testFullExportReadsLatestDurableDataWhileDiagnosticsRemainRedacted() throws {
        try withSetup { store, defaults in
            let original = try self.completedWorld()
            try store.save(original)
            let controller = self.controller(store, defaults)
            var newer = original
            newer.profile.lastIntention = "PRIVATE_SYNTHETIC_NEWER_INTENTION"
            try store.save(newer)
            let before = try Data(contentsOf: store.worldURL)

            let full = try XCTUnwrap(controller.prepareFullDataExport())
            let diagnostic = try XCTUnwrap(controller.prepareDiagnosticExport())
            let fullText = try XCTUnwrap(String(data: full, encoding: .utf8))
            let diagnosticText = try XCTUnwrap(String(data: diagnostic, encoding: .utf8))

            XCTAssertEqual(full, try store.exportCurrentWorldJSON())
            for marker in [
                "PRIVATE_SYNTHETIC_NEWER_INTENTION", "PRIVATE_SYNTHETIC_THOUGHT", "PRIVATE_SYNTHETIC_RECALL",
            ] {
                XCTAssertTrue(fullText.contains(marker))
            }
            XCTAssertFalse(diagnosticText.contains("PRIVATE_SYNTHETIC"))
            XCTAssertFalse(diagnosticText.contains(store.root.path))
            XCTAssertEqual(try Data(contentsOf: store.worldURL), before)
            XCTAssertNil(controller.activeIssue)
        }
    }

    func testInvalidDataIsPreservedThenExplicitDeletionRemovesOnlyOwnedArtifacts() throws {
        try withSetup { store, defaults in
            let invalid = Data("PRIVATE_SYNTHETIC_INVALID_WORLD".utf8)
            try invalid.write(to: store.worldURL)
            let neighbor = store.root.appendingPathComponent("unrelated-notes.txt")
            let neighborBytes = Data("synthetic unrelated file".utf8)
            try neighborBytes.write(to: neighbor)
            let controller = self.controller(store, defaults)
            controller.intentionDraft = "PRIVATE_SYNTHETIC_DRAFT"
            controller.start()
            controller.deleteAllData()

            XCTAssertTrue(controller.storeNeedsRecovery)
            XCTAssertNil(controller.prepareFullDataExport())
            XCTAssertEqual(try Data(contentsOf: store.worldURL), invalid)
            let diagnostic = try XCTUnwrap(controller.prepareDiagnosticExport())
            XCTAssertFalse(String(decoding: diagnostic, as: UTF8.self).contains("PRIVATE_SYNTHETIC"))

            controller.preserveAndResetStore()
            XCTAssertFalse(controller.storeNeedsRecovery)
            XCTAssertEqual(try store.load(), .empty)
            XCTAssertTrue(controller.intentionDraft.isEmpty)
            XCTAssertNil(controller.activeIssue)
            let preserved = try XCTUnwrap(self.quarantines(in: store).only)
            XCTAssertEqual(try Data(contentsOf: preserved), invalid)

            controller.captureDraft = "PRIVATE_SYNTHETIC_CAPTURE_DRAFT"
            controller.recallDraft = "PRIVATE_SYNTHETIC_RECALL_DRAFT"
            controller.deleteAllData()

            XCTAssertEqual(try store.load(), .empty)
            XCTAssertTrue(try self.quarantines(in: store).isEmpty)
            XCTAssertTrue(controller.captureDraft.isEmpty)
            XCTAssertTrue(controller.recallDraft.isEmpty)
            XCTAssertEqual(try Data(contentsOf: neighbor), neighborBytes)
            XCTAssertEqual(controller.userNotice, "All local Flowmo data was deleted.")
            XCTAssertNil(controller.activeIssue)
        }
    }

    func testPreserveAndResetCannotOverwriteAStoreRepairedSinceTheErrorWasShown() throws {
        try withSetup { store, defaults in
            try Data("synthetic invalid world".utf8).write(to: store.worldURL)
            let controller = self.controller(store, defaults)
            XCTAssertTrue(controller.canPreserveAndReset)
            let repaired = try self.completedWorld()
            try store.save(repaired)
            let before = try Data(contentsOf: store.worldURL)

            controller.preserveAndResetStore()

            XCTAssertEqual(controller.activeIssue?.code, .preserveAndResetFailed)
            XCTAssertEqual(try Data(contentsOf: store.worldURL), before)
            XCTAssertTrue(try self.quarantines(in: store).isEmpty)
            controller.retryStore()
            XCTAssertEqual(controller.world, repaired)
            XCTAssertFalse(controller.storeNeedsRecovery)
            XCTAssertNil(controller.activeIssue)
        }
    }

    func testPartialDeletionClearsCurrentDataButReportsTheRetainedArtifact() throws {
        try withSetup { store, defaults in
            try Data("synthetic invalid world".utf8).write(to: store.worldURL)
            let preserved = try store.quarantineInvalidWorldAndReset().quarantineURL
            try FileManager.default.removeItem(at: preserved)
            // A directory at an owned filename cannot be unlinked as a file.
            try FileManager.default.createDirectory(at: preserved, withIntermediateDirectories: false)
            try store.save(self.completedWorld())
            let controller = self.controller(store, defaults)
            controller.intentionDraft = "synthetic draft"

            controller.deleteAllData()

            XCTAssertEqual(try store.load(), .empty)
            XCTAssertEqual(controller.world, .empty)
            XCTAssertTrue(controller.intentionDraft.isEmpty)
            XCTAssertEqual(controller.activeIssue?.code, .dataDeletionIncomplete)
            XCTAssertTrue(FileManager.default.fileExists(atPath: preserved.path))
            XCTAssertNil(controller.userNotice)
        }
    }

    private func controller(_ store: Store, _ defaults: UserDefaults) -> PhoneSessionController {
        PhoneSessionController(
            store: store, mode: .localOnly, attention: PhoneAttention(notificationsEnabled: false),
            userDefaults: defaults
        )
    }

    private func completedWorld() throws -> World {
        var world = World.empty
        world.config.cuesEnabled = false
        var engine = Engine(world: world)
        let origin = Date(timeIntervalSince1970: 1_800_000_000)
        try engine.apply(.start(intention: "PRIVATE_SYNTHETIC_INTENTION"), now: origin)
        try engine.apply(.skip, now: origin)
        try engine.apply(.capture("PRIVATE_SYNTHETIC_THOUGHT"), now: origin.addingTimeInterval(10))
        try engine.apply(.stopFocus, now: origin.addingTimeInterval(100))
        try engine.apply(.skip, now: origin.addingTimeInterval(101))
        try engine.apply(.setRecallText("PRIVATE_SYNTHETIC_RECALL"), now: origin.addingTimeInterval(102))
        try engine.apply(.skip, now: origin.addingTimeInterval(103))
        try engine.apply(.skip, now: origin.addingTimeInterval(104))
        return engine.world
    }

    private func quarantines(in store: Store) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: store.root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("world.invalid-") }
    }

    private func withSetup(_ body: (Store, UserDefaults) throws -> Void) throws {
        let name = "flowmo-phone-data-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        try body(Store(root: root), defaults)
    }
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
