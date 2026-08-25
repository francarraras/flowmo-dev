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

    private func withStore(_ body: (WorldSyncMetadataStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(WorldSyncMetadataStore(root: root))
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
