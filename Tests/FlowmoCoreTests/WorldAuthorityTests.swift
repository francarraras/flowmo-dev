import Foundation
import XCTest

@testable import FlowmoCore

final class WorldAuthorityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testObservedContinueCommitsTheExactPausedSessionDurably() throws {
        try withStore { store in
            let paused = try pausedPrimeWorld(intention: "write the architecture note")
            try store.save(paused)
            let observedLive = try XCTUnwrap(paused.live)
            let continuedAt = start.addingTimeInterval(30)

            let result = try WorldAuthority(store: store).apply(
                .continue,
                observed: ObservedLiveBeat(observedLive),
                at: continuedAt
            )

            let commit = try XCTUnwrap(result.commit)
            XCTAssertEqual(commit.before, ObservedLiveBeat(observedLive))
            XCTAssertEqual(commit.after?.sessionID, observedLive.id)
            XCTAssertEqual(commit.after?.beat, .prime)
            XCTAssertFalse(try XCTUnwrap(commit.after).isRecoveryPaused)
            XCTAssertEqual(commit.world.live?.lastResumedAt, continuedAt)
            XCTAssertTrue(commit.changed)
            XCTAssertNil(commit.completedSession)
            XCTAssertEqual(try store.load(), commit.world)
        }
    }

    func testObservedRestartReturnsTheReplacementTransition() throws {
        try withStore { store in
            let paused = try pausedPrimeWorld(intention: "shape the action seam")
            try store.save(paused)
            let observedLive = try XCTUnwrap(paused.live)

            let result = try WorldAuthority(store: store).apply(
                .restart,
                observed: ObservedLiveBeat(observedLive),
                at: start.addingTimeInterval(40)
            )

            let commit = try XCTUnwrap(result.commit)
            let replacement = try XCTUnwrap(commit.world.live)
            XCTAssertEqual(commit.before?.sessionID, observedLive.id)
            XCTAssertNotEqual(replacement.id, observedLive.id)
            XCTAssertEqual(commit.after, ObservedLiveBeat(replacement))
            XCTAssertEqual(replacement.phase, .prime)
            XCTAssertEqual(replacement.intention, observedLive.intention)
            XCTAssertFalse(replacement.isPaused)
            XCTAssertEqual(try store.load(), commit.world)
        }
    }

    func testEveryObservedLiveBeatFactRejectsAStaleAction() throws {
        try withStore { store in
            let paused = try pausedPrimeWorld(intention: "protect the winner")
            try store.save(paused)
            let live = try XCTUnwrap(paused.live)
            let authority = WorldAuthority(store: store)
            let staleObservations = [
                ObservedLiveBeat(
                    sessionID: UUID(),
                    beat: live.phase,
                    isRecoveryPaused: true
                ),
                ObservedLiveBeat(
                    sessionID: live.id,
                    beat: .focus,
                    isRecoveryPaused: true
                ),
                ObservedLiveBeat(
                    sessionID: live.id,
                    beat: live.phase,
                    isRecoveryPaused: false
                ),
            ]

            for observed in staleObservations {
                let result = try authority.apply(
                    .restart,
                    observed: observed,
                    at: start.addingTimeInterval(50)
                )
                guard case .stale(let current) = result else {
                    return XCTFail("A mismatched observation must be rejected")
                }
                XCTAssertEqual(current, paused)
                XCTAssertEqual(try store.load(), paused)
            }
        }
    }

    func testCloseBeatCommitReturnsOnlyTheExactCompletedSessionAndNextStep() throws {
        try withStore { store in
            let older = CompletedSession(
                id: UUID(),
                intention: "older work",
                focusSeconds: 600,
                breakSeconds: 120,
                captureCount: 0,
                recallText: "do not carry this",
                endedAt: start.addingTimeInterval(-100)
            )
            let closeBeat = try closeBeatWorld(
                recallText: "  finish the migration note \n",
                history: [older]
            )
            try store.save(closeBeat)
            let observedLive = try XCTUnwrap(closeBeat.live)

            let result = try WorldAuthority(store: store).apply(
                .skip,
                observed: ObservedLiveBeat(observedLive),
                at: start.addingTimeInterval(64)
            )

            let commit = try XCTUnwrap(result.commit)
            XCTAssertNil(commit.world.live)
            XCTAssertEqual(commit.completedSession?.id, observedLive.id)
            XCTAssertEqual(commit.completedNextStep, "finish the migration note")
            XCTAssertEqual(commit.world.history.first?.id, older.id)
            XCTAssertEqual(commit.world.history.last?.id, observedLive.id)
            XCTAssertEqual(try store.load(), commit.world)
        }
    }

    func testBlankExactCompletionNeverFallsBackToOlderHistory() throws {
        try withStore { store in
            let older = CompletedSession(
                id: UUID(),
                intention: "older work",
                focusSeconds: 600,
                breakSeconds: 120,
                captureCount: 0,
                recallText: "older next step",
                endedAt: start.addingTimeInterval(-100)
            )
            let closeBeat = try closeBeatWorld(recallText: " \n ", history: [older])
            try store.save(closeBeat)
            let observedLive = try XCTUnwrap(closeBeat.live)

            let result = try WorldAuthority(store: store).apply(
                .skip,
                observed: ObservedLiveBeat(observedLive),
                at: start.addingTimeInterval(64)
            )

            let commit = try XCTUnwrap(result.commit)
            XCTAssertEqual(commit.completedSession?.id, observedLive.id)
            XCTAssertNil(commit.completedNextStep)
        }
    }

    private func pausedPrimeWorld(intention: String) throws -> World {
        var engine = Engine()
        try engine.apply(.start(intention: intention), now: start)
        try engine.apply(.pauseForRecovery, now: start.addingTimeInterval(10))
        return engine.world
    }

    private func closeBeatWorld(
        recallText: String,
        history: [CompletedSession]
    ) throws -> World {
        var world = World.empty
        world.history = history
        var engine = Engine(world: world)
        try engine.apply(.start(intention: "write the migration note"), now: start)
        try engine.apply(.skip, now: start.addingTimeInterval(1))
        try engine.apply(.stopFocus, now: start.addingTimeInterval(60))
        try engine.apply(.skip, now: start.addingTimeInterval(61))
        try engine.apply(.setRecallText(recallText), now: start.addingTimeInterval(62))
        try engine.apply(.skip, now: start.addingTimeInterval(63))
        return engine.world
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-world-authority-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }
}
