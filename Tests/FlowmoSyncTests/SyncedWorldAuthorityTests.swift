import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoSync

final class SyncedWorldAuthorityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testCommittedActionClearsExactRemoteOwnership() throws {
        try withStore { store in
            let world = try closeBeatWorld(recallText: "continue with tests")
            let live = try XCTUnwrap(world.live)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            let generation = UUID()
            try store.save(world)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: live.id,
                    base: WorldSyncSnapshot(world: world, generation: generation)
                )
            )

            let result = try WorldAuthority(
                store: store,
                syncMetadataStore: metadataStore
            ).apply(
                .skip,
                observed: ObservedLiveBeat(live),
                at: start.addingTimeInterval(64)
            )

            let commit = try XCTUnwrap(result.commit)
            XCTAssertTrue(commit.warnings.isEmpty)
            XCTAssertNil(commit.world.live)
            XCTAssertNil(try metadataStore.load().remoteLiveSessionID)
            XCTAssertEqual(try store.load(), commit.world)
        }
    }

    func testStaleActionDoesNotChangeWorldOrRemoteOwnership() throws {
        try withStore { store in
            let observedWorld = try closeBeatWorld(recallText: "stale next step")
            let observedLive = try XCTUnwrap(observedWorld.live)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            let generation = UUID()
            try store.save(observedWorld)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: observedLive.id,
                    base: WorldSyncSnapshot(world: observedWorld, generation: generation)
                )
            )
            let winningWorld = try store.update { engine in
                try engine.apply(.skip, now: start.addingTimeInterval(64))
                try engine.apply(
                    .start(intention: "replacement work"),
                    now: start.addingTimeInterval(65)
                )
            }.world

            let result = try WorldAuthority(
                store: store,
                syncMetadataStore: metadataStore
            ).apply(
                .skip,
                observed: ObservedLiveBeat(observedLive),
                at: start.addingTimeInterval(66)
            )

            guard case .stale(let current) = result else {
                return XCTFail("The replaced Close Beat must be stale")
            }
            XCTAssertEqual(current, winningWorld)
            XCTAssertEqual(try store.load(), winningWorld)
            XCTAssertEqual(try metadataStore.load().remoteLiveSessionID, observedLive.id)
        }
    }

    func testLocalActionDoesNotCreateUnchangedSyncMetadata() throws {
        try withStore { store in
            let world = try closeBeatWorld(recallText: "keep the store quiet")
            let live = try XCTUnwrap(world.live)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try store.save(world)

            let result = try WorldAuthority(
                store: store,
                syncMetadataStore: metadataStore
            ).apply(
                .skip,
                observed: ObservedLiveBeat(live),
                at: start.addingTimeInterval(64)
            )

            XCTAssertNotNil(result.commit)
            XCTAssertFalse(FileManager.default.fileExists(atPath: metadataStore.stateURL.path))
        }
    }

    func testStaleActionNeverTouchesUnreadableSyncMetadata() throws {
        try withStore { store in
            let observedWorld = try closeBeatWorld(recallText: "stale metadata proof")
            let observedLive = try XCTUnwrap(observedWorld.live)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try store.save(observedWorld)
            let winningWorld = try store.update { engine in
                try engine.apply(.skip, now: start.addingTimeInterval(64))
                try engine.apply(
                    .start(intention: "new local winner"),
                    now: start.addingTimeInterval(65)
                )
            }.world
            try FileManager.default.createDirectory(
                at: metadataStore.stateURL,
                withIntermediateDirectories: true
            )

            let result = try WorldAuthority(
                store: store,
                syncMetadataStore: metadataStore
            ).apply(
                .skip,
                observed: ObservedLiveBeat(observedLive),
                at: start.addingTimeInterval(66)
            )

            guard case .stale(let current) = result else {
                return XCTFail("The replaced action must remain a normal stale result")
            }
            XCTAssertEqual(current, winningWorld)
            XCTAssertEqual(try store.load(), winningWorld)
        }
    }

    func testMetadataFailureReturnsTheDurableWorldWithAWarning() throws {
        try withStore { store in
            let world = try closeBeatWorld(recallText: "durable next step")
            let live = try XCTUnwrap(world.live)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try store.save(world)
            try FileManager.default.createDirectory(
                at: metadataStore.stateURL,
                withIntermediateDirectories: true
            )

            let result = try WorldAuthority(
                store: store,
                syncMetadataStore: metadataStore
            ).apply(
                .skip,
                observed: ObservedLiveBeat(live),
                at: start.addingTimeInterval(64)
            )

            let commit = try XCTUnwrap(result.commit)
            XCTAssertEqual(commit.warnings, [.auxiliaryPersistenceFailed])
            XCTAssertNil(commit.world.live)
            XCTAssertEqual(commit.completedSession?.id, live.id)
            XCTAssertEqual(try store.load(), commit.world)
        }
    }

    private func closeBeatWorld(recallText: String) throws -> World {
        var engine = Engine()
        try engine.apply(.start(intention: "exercise synchronized authority"), now: start)
        try engine.apply(.skip, now: start.addingTimeInterval(1))
        try engine.apply(.stopFocus, now: start.addingTimeInterval(60))
        try engine.apply(.skip, now: start.addingTimeInterval(61))
        try engine.apply(.setRecallText(recallText), now: start.addingTimeInterval(62))
        try engine.apply(.skip, now: start.addingTimeInterval(63))
        return engine.world
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-synced-authority-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }
}
