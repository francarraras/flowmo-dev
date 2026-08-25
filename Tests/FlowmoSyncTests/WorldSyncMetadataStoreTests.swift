import FlowmoCore
import XCTest

@testable import FlowmoSync

final class WorldSyncMetadataStoreTests: XCTestCase {
    func testMetadataRoundTripsWithPrivateModeAndRemoteReplica() throws {
        try withStore { store in
            var world = World.empty
            world.profile.lastIntention = "private"
            let snapshot = WorldSyncSnapshot(world: world, generation: uuid(1))
            var metadata = WorldSyncMetadata(generation: uuid(1), base: snapshot, pending: snapshot)
            try metadata.replaceRemote(with: snapshot)

            try store.save(metadata)

            XCTAssertEqual(try store.load(), metadata)
            let attributes = try FileManager.default.attributesOfItem(atPath: store.stateURL.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testUnsafeStateSymlinkIsRejectedWithoutChangingTarget() throws {
        try withStore { store in
            let target = store.root.deletingLastPathComponent().appendingPathComponent("target")
            let planted = Data("untouched".utf8)
            try planted.write(to: target)
            try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: store.stateURL, withDestinationURL: target)

            XCTAssertThrowsError(try store.save(WorldSyncMetadata())) {
                XCTAssertEqual($0 as? WorldSyncMetadataError, .unsafeTarget)
            }
            XCTAssertEqual(try Data(contentsOf: target), planted)
        }
    }

    func testDeleteOwnedDataRemovesOnlyStateAndExactUUIDAssets() throws {
        try withStore { store in
            try store.save(WorldSyncMetadata())
            let revision = uuid(2)
            let asset = try store.writeAsset(Data("private".utf8), revision: revision)
            let similar = store.root.appendingPathComponent("asset-not-a-uuid.json")
            try Data("keep".utf8).write(to: similar)

            try store.deleteOwnedData()

            XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: asset.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: similar.path))
        }
    }

    func testPreparingDeletionForgetsPrivateReplicasAndKeepsOnlyCloudTombstones() throws {
        let session = CompletedSession(
            id: uuid(3),
            intention: "private deletion proof",
            focusSeconds: 600,
            breakSeconds: 120,
            captureCount: 1,
            recallText: "private recall",
            endedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var world = World.empty
        world.profile.lastIntention = "private profile"
        world.history = [session]
        let snapshot = WorldSyncSnapshot(world: world, generation: uuid(4))
        let sessionName = WorldSyncRecordCodec.sessionRecordName(session.id)
        var metadata = WorldSyncMetadata(
            generation: snapshot.head.generation,
            accountRecordName: "old-private-account-token",
            base: snapshot,
            pending: snapshot,
            recordSystemFields: [
                WorldSyncRecordCodec.headRecordName: Data("opaque-head-fields".utf8),
                sessionName: Data("opaque-session-fields".utf8),
            ]
        )
        try metadata.replaceRemote(with: snapshot)

        let empty = metadata.prepareDataDeletion()

        XCTAssertTrue(empty.isEffectivelyEmpty)
        XCTAssertNil(metadata.base)
        XCTAssertEqual(metadata.pending, empty)
        XCTAssertNil(metadata.conflict)
        XCTAssertNil(metadata.remoteHeadData)
        XCTAssertTrue(metadata.remoteSessionData.isEmpty)
        XCTAssertTrue(metadata.cloudDeletionPending)
        XCTAssertEqual(metadata.cloudDeletionAccountRecordName, "old-private-account-token")
        XCTAssertEqual(metadata.pendingDeletionRecordNames, [sessionName])
        XCTAssertEqual(metadata.recordSystemFields.count, 2)
        let encoded = String(decoding: try JSONEncoder.flowmo.encode(metadata), as: UTF8.self)
        XCTAssertFalse(encoded.contains("private deletion proof"))
        XCTAssertFalse(encoded.contains("private recall"))
        XCTAssertFalse(encoded.contains("private profile"))
    }

    func testMetadataWrittenBeforeDeletionQueueFieldStillDecodes() throws {
        try withStore { store in
            try store.save(WorldSyncMetadata(generation: uuid(5)))
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: store.stateURL)) as? [String: Any]
            )
            object.removeValue(forKey: "pendingDeletionRecordNames")
            try JSONSerialization.data(withJSONObject: object).write(to: store.stateURL)

            XCTAssertEqual(try store.load().pendingDeletionRecordNames, [])
            XCTAssertFalse(try store.load().cloudDeletionPending)
            XCTAssertNil(try store.load().cloudDeletionAccountRecordName)
        }
    }

    func testOrphanedRemoteSessionsAreForgottenAndQueuedForExactDeletion() throws {
        let first = completed(id: uuid(6))
        let orphan = completed(id: uuid(7))
        var allWorld = World.empty
        allWorld.history = [first, orphan]
        var referencedWorld = World.empty
        referencedWorld.history = [first]
        var metadata = WorldSyncMetadata()
        try metadata.replaceRemote(
            with: WorldSyncSnapshot(world: allWorld, generation: uuid(8))
        )

        let removed = metadata.forgetOrphanedRemoteSessions(
            referencedBy: WorldSyncSnapshot(world: referencedWorld, generation: uuid(8))
        )

        let orphanName = WorldSyncRecordCodec.sessionRecordName(orphan.id)
        XCTAssertEqual(removed, [orphanName])
        XCTAssertEqual(metadata.pendingDeletionRecordNames, [orphanName])
        XCTAssertNil(metadata.remoteSessionData[orphanName])
        XCTAssertNotNil(
            metadata.remoteSessionData[WorldSyncRecordCodec.sessionRecordName(first.id)]
        )
    }

    func testPendingDeletionNeverCrossesICloudAccounts() {
        var world = World.empty
        world.profile.lastIntention = "old account private data"
        var metadata = WorldSyncMetadata(
            accountRecordName: "old-account",
            base: WorldSyncSnapshot(world: world, generation: uuid(9))
        )
        metadata.prepareDataDeletion()

        metadata.prepareForAccountSwitch(to: "new-account")

        XCTAssertTrue(metadata.cloudDeletionPending)
        XCTAssertEqual(metadata.cloudDeletionAccountRecordName, "old-account")
        XCTAssertFalse(metadata.canSendCloudDeletion)
        XCTAssertFalse(metadata.accountChangeRequiresChoice)
        XCTAssertTrue(metadata.remoteSessionData.isEmpty)
        XCTAssertNil(metadata.remoteHeadData)

        metadata.prepareDataDeletion()

        XCTAssertEqual(metadata.cloudDeletionAccountRecordName, "old-account")
        XCTAssertFalse(metadata.canSendCloudDeletion)

        metadata.prepareForAccountSwitch(to: "old-account")

        XCTAssertTrue(metadata.cloudDeletionPending)
        XCTAssertTrue(metadata.canSendCloudDeletion)
    }

    private func withStore(_ body: (WorldSyncMetadataStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(WorldSyncMetadataStore(root: root))
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }

    private func completed(id: UUID) -> CompletedSession {
        CompletedSession(
            id: id,
            intention: "private",
            focusSeconds: 600,
            breakSeconds: 120,
            captureCount: 0,
            recallText: nil,
            endedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
