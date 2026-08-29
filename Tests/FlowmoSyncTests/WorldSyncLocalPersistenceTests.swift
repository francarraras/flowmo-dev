import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoSync

final class WorldSyncLocalPersistenceTests: XCTestCase {
    func testMutationReceivesLatestPersistedWorld() throws {
        try withPersistence { worldStore, metadataStore, persistence in
            var initial = World.empty
            initial.profile.lastIntention = "initial"
            try worldStore.save(initial)

            let latest = try worldStore.update { engine in
                engine.world.profile.lastIntention = "latest local change"
            }.world

            try metadataStore.save(WorldSyncMetadata(generation: uuid(1)))
            let commit = try persistence.commit { currentWorld, _ in
                WorldSyncLocalMutation(world: currentWorld, output: currentWorld)
            }

            XCTAssertEqual(commit.output, latest)
            XCTAssertEqual(commit.world, latest)
            XCTAssertFalse(commit.worldChanged)
            XCTAssertEqual(try worldStore.load(), latest)
        }
    }

    func testSharedRemoteStatePreservesDeviceOnlyConfiguration() throws {
        try withPersistence { worldStore, metadataStore, persistence in
            var local = World.empty
            local.config.cuesEnabled = false
            local.config.focusGuard = FocusGuardConfiguration(
                enabled: true,
                bundleIdentifiers: ["com.example.local"]
            )
            local.profile.recentFocusSeconds = [321]
            try worldStore.save(local)

            var remoteWorld = World.empty
            remoteWorld.profile.breakRatio = 4
            remoteWorld.profile.lastIntention = "remote next step"
            remoteWorld.history = [completedSession(id: uuid(2))]
            let remote = WorldSyncSnapshot(world: remoteWorld, generation: uuid(3))
            try metadataStore.save(WorldSyncMetadata(generation: remote.head.generation))

            let commit = try persistence.commit { currentWorld, nextMetadata in
                nextMetadata.base = remote
                return WorldSyncLocalMutation(
                    world: try remote.applying(to: currentWorld),
                    output: remote
                )
            }

            XCTAssertTrue(commit.worldChanged)
            XCTAssertEqual(commit.world.config, local.config)
            XCTAssertEqual(commit.world.profile.recentFocusSeconds, [321])
            XCTAssertEqual(commit.world.profile.breakRatio, 4)
            XCTAssertEqual(commit.world.profile.lastIntention, "remote next step")
            XCTAssertEqual(commit.world.history, remoteWorld.history)
            XCTAssertEqual(try worldStore.load(), commit.world)
            XCTAssertEqual(try metadataStore.load().base, remote)
        }
    }

    func testNoWorldChangeStillPersistsMetadata() throws {
        try withPersistence { worldStore, metadataStore, persistence in
            try worldStore.save(.empty)
            let generation = uuid(4)
            try metadataStore.save(WorldSyncMetadata(generation: generation))

            let commit = try persistence.commit { currentWorld, nextMetadata in
                nextMetadata.accountRecordName = "synthetic-account"
                return WorldSyncLocalMutation(world: currentWorld, output: ())
            }

            XCTAssertFalse(commit.worldChanged)
            XCTAssertEqual(commit.world, .empty)
            XCTAssertEqual(commit.metadata.accountRecordName, "synthetic-account")
            XCTAssertEqual(try metadataStore.load(), commit.metadata)
        }
    }

    func testCommitInitializesPreviouslyAbsentMetadata() throws {
        try withPersistence { _, metadataStore, persistence in
            let commit = try persistence.commit { currentWorld, nextMetadata in
                nextMetadata.accountRecordName = "first account"
                return WorldSyncLocalMutation(world: currentWorld, output: ())
            }

            XCTAssertEqual(commit.metadata.accountRecordName, "first account")
            XCTAssertEqual(try metadataStore.load(), commit.metadata)
        }
    }

    func testMetadataSaveFailureOccursAfterWorldIsDurable() throws {
        try withPersistence { worldStore, metadataStore, persistence in
            var initial = World.empty
            initial.profile.lastIntention = "before"
            try worldStore.save(initial)

            let originalMetadata = WorldSyncMetadata(generation: uuid(5))
            try metadataStore.save(originalMetadata)

            XCTAssertThrowsError(
                try persistence.commit { currentWorld, nextMetadata in
                    var changed = currentWorld
                    changed.profile.lastIntention = "durable world"
                    nextMetadata.schemaVersion = WorldSyncMetadata.schemaVersion + 1
                    return WorldSyncLocalMutation(world: changed, output: ())
                }
            ) { error in
                XCTAssertEqual(
                    error as? WorldSyncMetadataError,
                    .unsupportedSchema(WorldSyncMetadata.schemaVersion + 1)
                )
            }

            XCTAssertEqual(try worldStore.load().profile.lastIntention, "durable world")
            XCTAssertEqual(try metadataStore.load(), originalMetadata)
        }
    }

    func testCommitReloadsLatestLocalOwnershipMetadata() throws {
        try withPersistence { worldStore, metadataStore, persistence in
            let remoteSessionID = uuid(6)
            try worldStore.save(.empty)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: uuid(7),
                    remoteLiveSessionID: remoteSessionID
                )
            )
            try metadataStore.markLocalControl()

            let commit = try persistence.commit { currentWorld, nextMetadata in
                XCTAssertNil(nextMetadata.remoteLiveSessionID)
                nextMetadata.accountRecordName = "synthetic-account"
                return WorldSyncLocalMutation(world: currentWorld, output: ())
            }

            XCTAssertNil(commit.metadata.remoteLiveSessionID)
            XCTAssertNil(try metadataStore.load().remoteLiveSessionID)
        }
    }

    func testSubsequentMetadataWriterPreservesCommittedFields() throws {
        try withPersistence { worldStore, metadataStore, persistence in
            let remoteSessionID = uuid(8)
            try worldStore.save(.empty)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: uuid(9),
                    remoteLiveSessionID: remoteSessionID
                )
            )

            let commit = try persistence.commit { currentWorld, nextMetadata in
                var changed = currentWorld
                changed.profile.lastIntention = "durable world"
                nextMetadata.accountRecordName = "committed write"
                return WorldSyncLocalMutation(world: changed, output: ())
            }
            try metadataStore.markLocalControl()

            XCTAssertTrue(commit.worldChanged)
            XCTAssertEqual(try worldStore.load().profile.lastIntention, "durable world")
            let metadata = try metadataStore.load()
            XCTAssertNil(metadata.remoteLiveSessionID)
            XCTAssertEqual(metadata.accountRecordName, "committed write")
        }
    }

    private func withPersistence(
        _ body: (
            Store,
            WorldSyncMetadataStore,
            WorldSyncLocalPersistence
        ) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let worldStore = Store(root: root)
        let metadataStore = WorldSyncMetadataStore(root: root)
        try body(
            worldStore,
            metadataStore,
            WorldSyncLocalPersistence(
                worldStore: worldStore,
                metadataStore: metadataStore
            )
        )
    }

    private func completedSession(id: UUID) -> CompletedSession {
        CompletedSession(
            id: id,
            intention: "remote session",
            focusSeconds: 600,
            breakSeconds: 120,
            captureCount: 0,
            recallText: nil,
            endedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
