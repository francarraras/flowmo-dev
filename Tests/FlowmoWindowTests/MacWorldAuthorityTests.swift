import FlowmoCore
import FlowmoSync
import Foundation
import XCTest
import os

@testable import FlowmoWindow

@MainActor
final class MacWorldAuthorityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testLocalLiveRecoveryWriteAheadPrecedesWorldPersistence() throws {
        try withStore { store in
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            let order = RecordingAuthorityOrder()
            let recovery = RecordingRecoveryPersistence(
                store: store,
                metadataStore: metadataStore,
                order: order
            )
            let handoff = RecordingAuthorityHandoff(
                store: store,
                metadataStore: metadataStore,
                order: order
            )
            let authority = MacWorldAuthority(
                store: store,
                metadataStore: metadataStore,
                recovery: recovery,
                workContextHandoff: handoff
            )

            let outcome = authority.applyCurrent(
                .start(intention: "synthetic authority proof"),
                at: start
            )

            guard case .committed(let durable) = outcome else {
                return XCTFail("The local start should commit")
            }
            let observation = try XCTUnwrap(recovery.observations.first)
            guard case .writeAheadLive(let sessionID, let observedAt) = observation.mutation else {
                return XCTFail("A local Live Session must be written ahead")
            }
            XCTAssertEqual(sessionID, durable.action.world.live?.id)
            XCTAssertEqual(observedAt, start)
            XCTAssertNil(observation.world.live, "World must not be durable at write-ahead time")
            XCTAssertNil(observation.metadata)
            XCTAssertEqual(try store.load(), durable.action.world)
            XCTAssertEqual(order.steps, [.recovery(.writeAheadLive)])
            XCTAssertTrue(handoff.activations.isEmpty)
        }
    }

    func testExactRemotePrimeAdoptsRecoveryAfterWorldAndMetadataThenHandsOff() throws {
        try withStore { store in
            let prime = try primeWorld()
            let live = try XCTUnwrap(prime.live)
            let generation = UUID()
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try store.save(prime)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: live.id,
                    base: WorldSyncSnapshot(world: prime, generation: generation)
                )
            )
            let order = RecordingAuthorityOrder()
            let recovery = RecordingRecoveryPersistence(
                store: store,
                metadataStore: metadataStore,
                order: order
            )
            let handoff = RecordingAuthorityHandoff(
                store: store,
                metadataStore: metadataStore,
                order: order
            )
            let authority = MacWorldAuthority(
                store: store,
                metadataStore: metadataStore,
                recovery: recovery,
                workContextHandoff: handoff
            )
            let observedPrime = try XCTUnwrap(ObservedPrime(live))

            let outcome = authority.focusNow(
                observedPrime,
                at: start.addingTimeInterval(10)
            )

            guard case .committed(let durable) = outcome else {
                return XCTFail("The exact remote Prime should enter Focus")
            }
            XCTAssertNil(durable.syncWarning)
            XCTAssertEqual(durable.action.world.live?.phase, .focus)
            let observation = try XCTUnwrap(recovery.observations.first)
            guard case .adoptLiveAfterWorldPersistence(let sessionID, _) = observation.mutation else {
                return XCTFail("Remote ownership must be adopted after persistence")
            }
            XCTAssertEqual(sessionID, live.id)
            XCTAssertEqual(observation.world.live?.phase, .focus)
            XCTAssertNil(observation.metadata?.remoteLiveSessionID)
            XCTAssertEqual(try store.load(), durable.action.world)
            XCTAssertNil(try metadataStore.load().remoteLiveSessionID)
            XCTAssertEqual(
                order.steps,
                [
                    .recovery(.adoptLiveSession),
                    .handoffActivation,
                    .handoffRetention,
                ]
            )
            XCTAssertEqual(handoff.activations.map(\.sessionID), [live.id])
            XCTAssertEqual(handoff.activations.first?.worldPhase, .focus)
            XCTAssertNil(handoff.activations.first?.remoteLiveSessionID)
        }
    }

    func testSameIDRemoteMarkerWithDifferentSnapshotUsesLocalWriteAhead() throws {
        try withStore { store in
            let remotePrime = try primeWorld()
            let remoteLive = try XCTUnwrap(remotePrime.live)
            let generation = UUID()
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try metadataStore.save(
                WorldSyncMetadata(
                    generation: generation,
                    remoteLiveSessionID: remoteLive.id,
                    base: WorldSyncSnapshot(world: remotePrime, generation: generation)
                )
            )
            var localEngine = Engine(world: remotePrime)
            try localEngine.apply(.skip, now: start.addingTimeInterval(1))
            let localFocus = localEngine.world
            let localLive = try XCTUnwrap(localFocus.live)
            try store.save(localFocus)
            let recovery = RecordingRecoveryPersistence(
                store: store,
                metadataStore: metadataStore,
                order: RecordingAuthorityOrder()
            )
            let authority = MacWorldAuthority(
                store: store,
                metadataStore: metadataStore,
                recovery: recovery,
                workContextHandoff: RecordingAuthorityHandoff(
                    store: store,
                    metadataStore: metadataStore,
                    order: RecordingAuthorityOrder()
                )
            )

            let outcome = authority.apply(
                .stopFocus,
                observed: ObservedLiveBeat(localLive),
                at: start.addingTimeInterval(20)
            )

            guard case .committed = outcome else {
                return XCTFail("The same-ID local mutation should commit")
            }
            let observation = try XCTUnwrap(recovery.observations.first)
            guard case .writeAheadLive(let sessionID, _) = observation.mutation else {
                return XCTFail("A different snapshot with the same ID is local ownership")
            }
            XCTAssertEqual(sessionID, remoteLive.id)
            XCTAssertEqual(observation.world, localFocus)
        }
    }

    func testStaleFocusGestureTouchesNoMetadataRecoveryOrHandoff() throws {
        try withStore { store in
            let prime = try primeWorld()
            let observedPrime = try XCTUnwrap(ObservedPrime(prime.live))
            try store.save(prime)
            let winningWorld = try store.update { engine in
                try engine.apply(.skip, now: start.addingTimeInterval(1))
            }.world
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try FileManager.default.createDirectory(
                at: metadataStore.stateURL,
                withIntermediateDirectories: true
            )
            let order = RecordingAuthorityOrder()
            let recovery = RecordingRecoveryPersistence(
                store: store,
                metadataStore: metadataStore,
                order: order
            )
            let handoff = RecordingAuthorityHandoff(
                store: store,
                metadataStore: metadataStore,
                order: order
            )
            let authority = MacWorldAuthority(
                store: store,
                metadataStore: metadataStore,
                recovery: recovery,
                workContextHandoff: handoff
            )

            let outcome = authority.focusNow(
                observedPrime,
                at: start.addingTimeInterval(2)
            )

            guard case .stale(let current) = outcome else {
                return XCTFail("The replaced Prime gesture must be stale")
            }
            XCTAssertEqual(current, winningWorld)
            XCTAssertEqual(try store.load(), winningWorld)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: metadataStore.stateURL.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            XCTAssertTrue(recovery.observations.isEmpty)
            XCTAssertTrue(handoff.activations.isEmpty)
            XCTAssertTrue(order.steps.isEmpty)
        }
    }

    func testSyncFailureIsAWarningOnTheDurableCommit() throws {
        try withStore { store in
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            try FileManager.default.createDirectory(
                at: metadataStore.stateURL,
                withIntermediateDirectories: true
            )
            let recovery = RecordingRecoveryPersistence(
                store: store,
                metadataStore: metadataStore,
                order: RecordingAuthorityOrder()
            )
            let authority = MacWorldAuthority(
                store: store,
                metadataStore: metadataStore,
                recovery: recovery,
                workContextHandoff: RecordingAuthorityHandoff(
                    store: store,
                    metadataStore: metadataStore,
                    order: RecordingAuthorityOrder()
                )
            )

            let outcome = authority.applyCurrent(
                .start(intention: "synthetic sync warning"),
                at: start
            )

            guard case .committed(let durable) = outcome else {
                return XCTFail("Sync metadata failure must not erase a durable World")
            }
            XCTAssertEqual(durable.syncWarning, .metadataUnavailable)
            XCTAssertEqual(try store.load(), durable.action.world)
            XCTAssertEqual(recovery.observations.first?.world, .empty)
            guard case .writeAheadLive = recovery.observations.first?.mutation else {
                return XCTFail("Unknown ownership must fail closed to local recovery write-ahead")
            }
        }
    }

    func testWriteAheadFailureReturnsTypedNoCommit() throws {
        try withStore { store in
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            let recovery = RecordingRecoveryPersistence(
                store: store,
                metadataStore: metadataStore,
                order: RecordingAuthorityOrder(),
                failurePoint: .writeAheadLive
            )
            let handoff = RecordingAuthorityHandoff(
                store: store,
                metadataStore: metadataStore,
                order: RecordingAuthorityOrder()
            )
            let authority = MacWorldAuthority(
                store: store,
                metadataStore: metadataStore,
                recovery: recovery,
                workContextHandoff: handoff
            )

            let outcome = authority.applyCurrent(
                .start(intention: "synthetic failed write-ahead"),
                at: start
            )

            guard case .notCommitted(let failure) = outcome else {
                return XCTFail("Write-ahead failure must be a pre-persist no-commit")
            }
            XCTAssertEqual(failure.stage, .recoveryWriteAhead)
            XCTAssertTrue(failure.underlyingError is RecordingRecoveryError)
            XCTAssertEqual(try store.load(), .empty)
            XCTAssertNil(recovery.observations.first?.world.live)
            XCTAssertFalse(FileManager.default.fileExists(atPath: metadataStore.stateURL.path))
            XCTAssertTrue(handoff.activations.isEmpty)
        }
    }

    func testTerminalRecoveryFailureReturnsDurableBlockingResult() throws {
        try withStore { store in
            let closeBeat = try closeBeatWorld()
            let live = try XCTUnwrap(closeBeat.live)
            try store.save(closeBeat)
            let metadataStore = WorldSyncMetadataStore(root: store.root)
            let recovery = RecordingRecoveryPersistence(
                store: store,
                metadataStore: metadataStore,
                order: RecordingAuthorityOrder(),
                failurePoint: .clearTerminalMarker
            )
            let handoff = RecordingAuthorityHandoff(
                store: store,
                metadataStore: metadataStore,
                order: RecordingAuthorityOrder()
            )
            let authority = MacWorldAuthority(
                store: store,
                metadataStore: metadataStore,
                recovery: recovery,
                workContextHandoff: handoff
            )

            let outcome = authority.apply(
                .skip,
                observed: ObservedLiveBeat(live),
                at: start.addingTimeInterval(64)
            )

            guard case .committedRecoveryBlocked(let durable, let failure) = outcome else {
                return XCTFail("Post-persist recovery failure must preserve the durable commit")
            }
            XCTAssertEqual(failure.operation, .clearTerminalMarker)
            XCTAssertTrue(failure.underlyingError is RecordingRecoveryError)
            XCTAssertNil(durable.action.world.live)
            XCTAssertEqual(durable.action.completedSession?.id, live.id)
            XCTAssertEqual(try store.load(), durable.action.world)
            XCTAssertNil(recovery.observations.first?.world.live)
            guard case .clearAfterWorldPersistence = recovery.observations.first?.mutation else {
                return XCTFail("Terminal recovery metadata may clear only after World")
            }
            XCTAssertTrue(handoff.activations.isEmpty)
        }
    }

    private func primeWorld() throws -> World {
        var engine = Engine()
        try engine.apply(.start(intention: "synthetic authority proof"), now: start)
        return engine.world
    }

    private func closeBeatWorld() throws -> World {
        var engine = Engine()
        try engine.apply(.start(intention: "synthetic authority proof"), now: start)
        try engine.apply(.skip, now: start.addingTimeInterval(1))
        try engine.apply(.stopFocus, now: start.addingTimeInterval(60))
        try engine.apply(.skip, now: start.addingTimeInterval(61))
        try engine.apply(.setRecallText("synthetic next step"), now: start.addingTimeInterval(62))
        try engine.apply(.skip, now: start.addingTimeInterval(63))
        return engine.world
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-mac-authority-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }
}

private enum RecordingRecoveryError: Error, Sendable {
    case requestedFailure
}

private final class RecordingRecoveryPersistence: MacRecoveryPersistence, Sendable {
    enum FailurePoint: Equatable, Sendable {
        case writeAheadLive
        case adoptLiveSession
        case clearTerminalMarker
    }

    struct Observation: Equatable, Sendable {
        let mutation: MacRecoveryMutation
        let world: World
        let metadata: WorldSyncMetadata?
    }

    private struct State: Sendable {
        var observations: [Observation] = []
    }

    private let store: Store
    private let metadataStore: WorldSyncMetadataStore
    private let order: RecordingAuthorityOrder
    private let failurePoint: FailurePoint?
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        store: Store,
        metadataStore: WorldSyncMetadataStore,
        order: RecordingAuthorityOrder,
        failurePoint: FailurePoint? = nil
    ) {
        self.store = store
        self.metadataStore = metadataStore
        self.order = order
        self.failurePoint = failurePoint
    }

    var observations: [Observation] {
        state.withLock { $0.observations }
    }

    func persist(_ mutation: MacRecoveryMutation) throws {
        let world = try store.load()
        let observation = Observation(
            mutation: mutation,
            world: world,
            metadata: loadMetadataWithoutLock()
        )
        state.withLock { $0.observations.append(observation) }
        order.record(.recovery(orderingOperation(for: mutation)))
        if failurePoint == orderingOperation(for: mutation) {
            throw RecordingRecoveryError.requestedFailure
        }
    }

    private func loadMetadataWithoutLock() -> WorldSyncMetadata? {
        guard let data = try? Data(contentsOf: metadataStore.stateURL) else { return nil }
        return try? JSONDecoder.flowmo.decode(WorldSyncMetadata.self, from: data)
    }

    private func orderingOperation(
        for mutation: MacRecoveryMutation
    ) -> FailurePoint {
        switch mutation {
        case .writeAheadLive:
            return .writeAheadLive
        case .adoptLiveAfterWorldPersistence:
            return .adoptLiveSession
        case .clearAfterWorldPersistence:
            return .clearTerminalMarker
        }
    }
}

private final class RecordingAuthorityOrder: Sendable {
    enum Step: Equatable, Sendable {
        case recovery(RecordingRecoveryPersistence.FailurePoint)
        case handoffActivation
        case handoffRetention
    }

    private let state = OSAllocatedUnfairLock(initialState: [Step]())

    var steps: [Step] {
        state.withLock { $0 }
    }

    func record(_ step: Step) {
        state.withLock { $0.append(step) }
    }
}

@MainActor
private final class RecordingAuthorityHandoff: WorkContextHandoff {
    struct Activation: Equatable {
        let sessionID: UUID
        let worldPhase: SessionPhase?
        let remoteLiveSessionID: UUID?
    }

    private let store: Store
    private let metadataStore: WorldSyncMetadataStore
    private let order: RecordingAuthorityOrder
    private(set) var activations: [Activation] = []

    init(
        store: Store,
        metadataStore: WorldSyncMetadataStore,
        order: RecordingAuthorityOrder
    ) {
        self.store = store
        self.metadataStore = metadataStore
        self.order = order
    }

    func bindCandidate(to sessionID: UUID) {}

    func activateBoundTarget(
        for sessionID: UUID,
        excludingBundleIdentifiers: Set<String>
    ) {
        let metadata: WorldSyncMetadata?
        if let data = try? Data(contentsOf: metadataStore.stateURL) {
            metadata = try? JSONDecoder.flowmo.decode(WorldSyncMetadata.self, from: data)
        } else {
            metadata = nil
        }
        activations.append(
            Activation(
                sessionID: sessionID,
                worldPhase: try? store.load().live?.phase,
                remoteLiveSessionID: metadata?.remoteLiveSessionID
            )
        )
        order.record(.handoffActivation)
    }

    func transferBoundTarget(from oldSessionID: UUID, to newSessionID: UUID) {}

    func retainOnly(sessionID: UUID?) {
        order.record(.handoffRetention)
    }
}
