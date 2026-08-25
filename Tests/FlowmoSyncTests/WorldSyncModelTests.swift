import FlowmoCore
import XCTest

@testable import FlowmoSync

final class WorldSyncModelTests: XCTestCase {
    private let generation = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testBootstrapAdoptsRemoteWhenLocalIsEmpty() {
        let local = snapshot(world: .empty)
        let remote = snapshot(world: world(live: live(id: uuid(1), intention: "remote")))

        XCTAssertEqual(WorldSyncReconciler.bootstrap(local: local, remote: remote), .merged(remote))
    }

    func testBootstrapRequiresChoiceForTwoIndependentStores() throws {
        let local = snapshot(world: world(live: live(id: uuid(1), intention: "local")))
        let remote = snapshot(world: world(live: live(id: uuid(2), intention: "remote")))

        guard case .conflict(let conflict) = WorldSyncReconciler.bootstrap(local: local, remote: remote) else {
            return XCTFail("Expected an initial-import conflict")
        }
        XCTAssertEqual(conflict.kind, .initialImport)
        XCTAssertEqual(conflict.local.head.live?.intention, "local")
        XCTAssertEqual(conflict.remote.head.live?.intention, "remote")
    }

    func testIndependentCompletedSessionsUnionWithoutConflict() throws {
        let ancestor = snapshot(world: .empty)
        let localSession = completed(id: uuid(1), intention: "local", endedAt: start)
        let remoteSession = completed(id: uuid(2), intention: "remote", endedAt: start.addingTimeInterval(1))
        let local = snapshot(world: world(history: [localSession]))
        let remote = snapshot(world: world(history: [remoteSession]))

        guard
            case .merged(let merged) = WorldSyncReconciler.reconcile(
                local: local,
                remote: remote,
                ancestor: ancestor
            )
        else {
            return XCTFail("Expected append-only history to merge")
        }
        XCTAssertEqual(Set(merged.history.map(\.id)), [localSession.id, remoteSession.id])
    }

    func testSimultaneousOfflineStartsBecomeVisibleConflict() throws {
        let ancestor = snapshot(world: .empty)
        let local = snapshot(world: world(live: live(id: uuid(1), intention: "local")))
        let remote = snapshot(world: world(live: live(id: uuid(2), intention: "remote")))

        guard
            case .conflict(let conflict) = WorldSyncReconciler.reconcile(
                local: local,
                remote: remote,
                ancestor: ancestor
            )
        else {
            return XCTFail("Expected a live-session conflict")
        }
        XCTAssertEqual(conflict.kind, .liveSession)
    }

    func testResolvingLiveConflictPreservesIndependentHistory() throws {
        let localHistory = completed(id: uuid(3), intention: "local history", endedAt: start)
        let remoteHistory = completed(id: uuid(4), intention: "remote history", endedAt: start)
        let local = snapshot(world: world(live: live(id: uuid(1), intention: "local"), history: [localHistory]))
        let remote = snapshot(
            world: world(live: live(id: uuid(2), intention: "remote"), history: [remoteHistory]))
        let conflict = WorldSyncConflict(
            kind: .liveSession, local: local, remote: remote, ancestor: snapshot(world: .empty))

        let resolved = WorldSyncReconciler.resolve(conflict, choosing: .remote)

        XCTAssertEqual(resolved.head.live?.id, remote.head.live?.id)
        XCTAssertEqual(Set(resolved.history.map(\.id)), [localHistory.id, remoteHistory.id])
    }

    func testRemoteResetWinsWhenLocalDidNotChangeGeneration() throws {
        let oldGeneration = generation
        let newGeneration = uuid(9)
        let ancestor = snapshot(world: world(live: live(id: uuid(1), intention: "old")), generation: oldGeneration)
        let local = ancestor
        let remote = snapshot(world: .empty, generation: newGeneration)

        XCTAssertEqual(
            WorldSyncReconciler.reconcile(local: local, remote: remote, ancestor: ancestor),
            .merged(remote)
        )
    }

    func testApplyingRemoteStateKeepsDeviceOnlyConfigurationAndLegacySamples() throws {
        var local = World.empty
        local.config.cuesEnabled = false
        local.config.focusGuard = FocusGuardConfiguration(enabled: true, bundleIdentifiers: ["com.example.local"])
        local.profile.recentFocusSeconds = [600]
        let session = completed(id: uuid(1), intention: "done", endedAt: start)
        let remote = snapshot(world: world(history: [session], ratio: 4.5, lastIntention: "next"))

        let applied = try remote.applying(to: local)

        XCTAssertFalse(applied.config.cuesEnabled)
        XCTAssertEqual(applied.config.focusGuard.bundleIdentifiers, ["com.example.local"])
        XCTAssertEqual(applied.profile.recentFocusSeconds, [600])
        XCTAssertEqual(applied.profile.breakRatio, 4.5)
        XCTAssertEqual(applied.profile.lastIntention, "next")
        XCTAssertEqual(applied.profile.sessionCount, 1)
        XCTAssertEqual(applied.profile.totalFocusSeconds, 600)
    }

    private func snapshot(world: World, generation: UUID? = nil) -> WorldSyncSnapshot {
        WorldSyncSnapshot(world: world, generation: generation ?? self.generation)
    }

    private func world(
        live: SessionSnapshot? = nil,
        history: [CompletedSession] = [],
        ratio: Double = 5,
        lastIntention: String = ""
    ) -> World {
        var world = World.empty
        world.live = live
        world.history = history
        world.profile.breakRatio = ratio
        world.profile.lastIntention = lastIntention
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

    private func completed(id: UUID, intention: String, endedAt: Date) -> CompletedSession {
        CompletedSession(
            id: id,
            intention: intention,
            focusSeconds: 600,
            breakSeconds: 120,
            captureCount: 0,
            recallText: nil,
            endedAt: endedAt
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
