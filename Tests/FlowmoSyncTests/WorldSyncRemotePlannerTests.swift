import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoSync

final class WorldSyncRemotePlannerTests: XCTestCase {
    private let generation = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testBackgroundRefreshCannotClearAnExistingSessionConflict() throws {
        let ancestor = WorldSyncSnapshot(world: .empty, generation: generation)
        let localWorld = world(live: live(id: uuid(1), intention: "local"))
        let local = WorldSyncSnapshot(world: localWorld, generation: generation)
        let remote = WorldSyncSnapshot(
            world: world(live: live(id: uuid(2), intention: "remote")),
            generation: generation
        )
        guard
            case .conflict(let conflict) = WorldSyncReconciler.reconcile(
                local: local,
                remote: remote,
                ancestor: ancestor
            )
        else {
            return XCTFail("Expected a Live Session conflict")
        }

        var metadata = WorldSyncMetadata(
            generation: generation,
            base: ancestor,
            conflict: conflict
        )
        // A later remote refresh now looks mergeable, but it cannot choose for
        // the person who is still looking at the persisted conflict.
        try metadata.replaceRemote(with: ancestor)

        XCTAssertFalse(
            try WorldSyncRemotePlanner.remoteFactsMatch(
                conflict,
                metadata: metadata
            )
        )

        let background = try WorldSyncRemotePlanner.process(
            currentWorld: localWorld,
            metadata: &metadata,
            reconcileExistingConflict: false
        )

        XCTAssertEqual(background.world, localWorld)
        XCTAssertEqual(background.output, .conflict(conflict))
        XCTAssertEqual(metadata.conflict, conflict)
        XCTAssertNil(metadata.pending)

        let explicitlyRetried = try WorldSyncRemotePlanner.process(
            currentWorld: localWorld,
            metadata: &metadata,
            reconcileExistingConflict: true
        )

        XCTAssertEqual(explicitlyRetried.world, localWorld)
        XCTAssertEqual(
            explicitlyRetried.output,
            .merged(snapshot: local, remote: ancestor)
        )
        XCTAssertNil(metadata.conflict)
    }

    func testConflictChoiceRequiresTheRemoteFactsThatWerePresented() throws {
        let local = WorldSyncSnapshot(
            world: world(live: live(id: uuid(3), intention: "local")),
            generation: generation
        )
        let remote = WorldSyncSnapshot(
            world: world(live: live(id: uuid(4), intention: "remote")),
            generation: generation
        )
        let conflict = WorldSyncConflict(
            kind: .liveSession,
            local: local,
            remote: remote,
            ancestor: WorldSyncSnapshot(world: .empty, generation: generation)
        )
        var metadata = WorldSyncMetadata(generation: generation, conflict: conflict)
        try metadata.replaceRemote(with: remote)

        XCTAssertTrue(
            try WorldSyncRemotePlanner.remoteFactsMatch(
                conflict,
                metadata: metadata
            )
        )

        try metadata.replaceRemote(with: local)
        XCTAssertFalse(
            try WorldSyncRemotePlanner.remoteFactsMatch(
                conflict,
                metadata: metadata
            )
        )
    }

    func testMissingRemoteFactsMatchOnlySyntheticEmptyConflicts() throws {
        let local = WorldSyncSnapshot(
            world: world(live: live(id: uuid(5), intention: "local")),
            generation: generation
        )
        let empty = WorldSyncSnapshot(world: .empty, generation: uuid(6))
        let metadata = WorldSyncMetadata(generation: generation)

        for kind in [WorldSyncConflictKind.account, .resetGeneration] {
            let conflict = WorldSyncConflict(
                kind: kind,
                local: local,
                remote: empty,
                ancestor: nil
            )
            XCTAssertTrue(
                try WorldSyncRemotePlanner.remoteFactsMatch(
                    conflict,
                    metadata: metadata
                )
            )
        }

        let initialImport = WorldSyncConflict(
            kind: .initialImport,
            local: local,
            remote: empty,
            ancestor: nil
        )
        XCTAssertFalse(
            try WorldSyncRemotePlanner.remoteFactsMatch(
                initialImport,
                metadata: metadata
            )
        )
    }

    private func world(live: SessionSnapshot?) -> World {
        var world = World.empty
        world.live = live
        return world
    }

    private func live(id: UUID, intention: String) -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            intention: intention,
            phase: .focus,
            breakRatio: 5,
            startedAt: start,
            phaseStartedAt: start,
            focusStartedAt: start,
            focusEndedAt: nil,
            breakStartedAt: nil,
            breakDuration: nil,
            captures: [],
            primeDuration: 120,
            recallDuration: 180
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
