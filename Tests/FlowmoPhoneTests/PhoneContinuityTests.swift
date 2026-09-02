import FlowmoCore
import FlowmoSync
import Foundation
import XCTest

@testable import FlowmoPhone

@MainActor
final class PhoneContinuityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testSelectedHistorySessionFillsDraftWithoutStarting() throws {
        try withStore { store in
            let session = CompletedSession(
                id: UUID(),
                intention: "Draft the launch page",
                focusSeconds: 1_200,
                breakSeconds: 240,
                captureCount: 0,
                recallText: "Write the pricing section",
                endedAt: Date()
            )
            var world = World.empty
            world.history = [session]
            try store.save(world)
            let controller = makeController(store: store)
            let idleWorld = controller.world

            XCTAssertTrue(controller.useSessionResumption(session))
            XCTAssertEqual(controller.intentionDraft, "Write the pricing section")
            XCTAssertNil(controller.world.live)
            XCTAssertEqual(controller.world, idleWorld)
            XCTAssertEqual(try store.load(), idleWorld)
        }
    }

    func testSelectedHistorySessionRequiresExplicitReplacementOfTypedDraft() throws {
        try withStore { store in
            let session = CompletedSession(
                id: UUID(),
                intention: "Draft the launch page",
                focusSeconds: 1_200,
                breakSeconds: 240,
                captureCount: 0,
                recallText: "Write the pricing section",
                endedAt: Date()
            )
            var world = World.empty
            world.history = [session]
            try store.save(world)
            let storedWorld = try store.load()
            let controller = makeController(store: store)
            controller.intentionDraft = "Keep this draft"

            XCTAssertFalse(controller.useSessionResumption(session))
            XCTAssertEqual(controller.intentionDraft, "Keep this draft")
            XCTAssertTrue(
                controller.useSessionResumption(session, replacingCurrentDraft: true)
            )
            XCTAssertEqual(controller.intentionDraft, "Write the pricing section")
            XCTAssertEqual(try store.load(), storedWorld)
        }
    }

    func testParkedThoughtPromotionPersistsNextStepAndKeepsCaptures() throws {
        try withStore { store in
            let controller = try makeRecallController(store: store)
            let captures = try XCTUnwrap(controller.world.live?.captures)
            let selected = try XCTUnwrap(captures.last)

            XCTAssertTrue(controller.useParkedThoughtAsNext(selected))
            XCTAssertEqual(controller.recallDraft, selected.text)
            XCTAssertEqual(controller.world.live?.recallText, selected.text)
            XCTAssertEqual(controller.world.live?.captures, captures)

            let persisted = try store.load()
            XCTAssertEqual(persisted.live?.recallText, selected.text)
            XCTAssertEqual(persisted.live?.captures, captures)
        }
    }

    func testParkedThoughtPromotionNeverOverwritesTypedOrStoredRecall() throws {
        try withStore { store in
            let controller = try makeRecallController(store: store)
            let selected = try XCTUnwrap(controller.world.live?.captures.last)

            controller.recallDraft = "Already typed"
            XCTAssertFalse(controller.useParkedThoughtAsNext(selected))
            XCTAssertEqual(controller.recallDraft, "Already typed")
            XCTAssertEqual(controller.world.live?.recallText, "")

            controller.persistRecall()
            XCTAssertEqual(controller.world.live?.recallText, "Already typed")
            controller.recallDraft = ""

            XCTAssertFalse(controller.useParkedThoughtAsNext(selected))
            XCTAssertEqual(controller.recallDraft, "")
            XCTAssertEqual(controller.world.live?.recallText, "Already typed")
            XCTAssertEqual(try store.load().live?.recallText, "Already typed")
        }
    }

    func testParkedThoughtPromotionRejectsStaleCaptureWrongPhaseAndNoLiveSession() throws {
        try withStore { store in
            let controller = try makeRecallController(store: store)
            let captures = try XCTUnwrap(controller.world.live?.captures)
            let selected = try XCTUnwrap(captures.last)
            let stale = CaptureItem(
                text: selected.text,
                createdAt: selected.createdAt.addingTimeInterval(1)
            )

            XCTAssertFalse(controller.useParkedThoughtAsNext(stale))
            XCTAssertEqual(controller.world.live?.recallText, "")
            XCTAssertEqual(controller.world.live?.captures, captures)

            controller.skip()
            XCTAssertEqual(controller.world.live?.phase, .closeBeat)
            XCTAssertFalse(controller.useParkedThoughtAsNext(selected))
            XCTAssertEqual(controller.world.live?.recallText, "")
            XCTAssertEqual(controller.world.live?.captures, captures)

            controller.dismissCloseBeat()
            XCTAssertNil(controller.world.live)
            XCTAssertFalse(controller.useParkedThoughtAsNext(selected))
        }
    }

    func testParkedThoughtPromotionDoesNotOverwriteRecallSavedByAnotherSurface() throws {
        try withStore { store in
            let controller = try makeRecallController(store: store)
            let captures = try XCTUnwrap(controller.world.live?.captures)
            let selected = try XCTUnwrap(captures.last)

            _ = try store.update { engine in
                try engine.apply(.setRecallText("Saved elsewhere"), now: Date())
            }

            XCTAssertFalse(controller.useParkedThoughtAsNext(selected))
            XCTAssertEqual(controller.recallDraft, "Saved elsewhere")
            XCTAssertEqual(controller.world.live?.recallText, "Saved elsewhere")
            XCTAssertEqual(controller.world.live?.captures, captures)
            XCTAssertEqual(try store.load().live?.recallText, "Saved elsewhere")
        }
    }

    func testCloseDoneCarriesExactNextStepIntoEditableIdleWithoutStarting() throws {
        try withStore { store in
            let sessionID = try saveCloseBeatSession(
                to: store,
                recallText: "  finish the conclusion \n"
            )
            let controller = makeController(store: store)

            controller.dismissCloseBeat()

            XCTAssertNil(controller.world.live)
            XCTAssertEqual(controller.intentionDraft, "finish the conclusion")
            XCTAssertEqual(controller.world.history.last?.id, sessionID)
            XCTAssertEqual(try store.load(), controller.world)

            controller.intentionDraft = "finish and proofread the conclusion"
            controller.start()
            XCTAssertEqual(controller.world.live?.phase, .prime)
            XCTAssertEqual(
                controller.world.live?.intention,
                "finish and proofread the conclusion"
            )
        }
    }

    func testStaleFocusCaptureCannotLandOnAReplacementSession() throws {
        try withStore { store in
            var observed = Engine()
            try observed.apply(.start(intention: "synthetic original focus"), now: start)
            try observed.apply(.skip, now: start.addingTimeInterval(1))
            try store.save(observed.world)
            try markRemote(observed.world, in: store)
            let controller = makeController(store: store)

            var replacement = Engine()
            try replacement.apply(
                .start(intention: "synthetic replacement focus"),
                now: start.addingTimeInterval(2)
            )
            try replacement.apply(.skip, now: start.addingTimeInterval(3))
            try store.save(replacement.world)

            controller.captureDraft = "synthetic stale capture"
            controller.showCapture = true
            controller.submitCapture()

            XCTAssertEqual(controller.world, replacement.world)
            XCTAssertEqual(try store.load(), replacement.world)
            XCTAssertTrue(try XCTUnwrap(controller.world.live).captures.isEmpty)
            XCTAssertEqual(controller.captureDraft, "synthetic stale capture")
            XCTAssertTrue(controller.showCapture)
        }
    }

    func testStaleEndFocusCannotStopAReplacementSession() throws {
        try withStore { store in
            var observed = Engine()
            try observed.apply(.start(intention: "synthetic original focus"), now: start)
            try observed.apply(.skip, now: start.addingTimeInterval(1))
            try store.save(observed.world)
            try markRemote(observed.world, in: store)
            let controller = makeController(store: store)

            var replacement = Engine()
            try replacement.apply(
                .start(intention: "synthetic replacement focus"),
                now: start.addingTimeInterval(2)
            )
            try replacement.apply(.skip, now: start.addingTimeInterval(3))
            try store.save(replacement.world)

            controller.stopFocus()

            XCTAssertEqual(controller.world, replacement.world)
            XCTAssertEqual(try store.load(), replacement.world)
            XCTAssertEqual(controller.world.live?.phase, .focus)
        }
    }

    func testStaleRecoveryContinueCannotResumeAReplacementSession() throws {
        try withStore { store in
            let observed = try pausedPrimeWorld(intention: "original task")
            try store.save(observed)
            let controller = makeController(store: store)

            let winningWorld = try replaceWithPausedPrime(in: store)
            controller.continueSession()

            XCTAssertEqual(controller.world, winningWorld)
            XCTAssertEqual(try store.load(), winningWorld)
            XCTAssertTrue(controller.world.live?.isPaused == true)
        }
    }

    func testStaleRecoveryRestartCannotReplaceAReplacementSession() throws {
        try withStore { store in
            let observed = try pausedPrimeWorld(intention: "original task")
            try store.save(observed)
            let controller = makeController(store: store)

            let winningWorld = try replaceWithPausedPrime(in: store)
            controller.restartSession()

            XCTAssertEqual(controller.world, winningWorld)
            XCTAssertEqual(try store.load(), winningWorld)
            XCTAssertTrue(controller.world.live?.isPaused == true)
        }
    }

    func testCloseDoneWithBlankNextStepNeverFallsBackToOlderWork() throws {
        try withStore { store in
            let older = CompletedSession(
                id: UUID(),
                intention: "older task",
                focusSeconds: 600,
                breakSeconds: 120,
                captureCount: 0,
                recallText: "do not carry this",
                endedAt: start.addingTimeInterval(-100)
            )
            _ = try saveCloseBeatSession(
                to: store,
                recallText: " \n ",
                history: [older]
            )
            let controller = makeController(store: store)

            controller.dismissCloseBeat()

            XCTAssertNil(controller.world.live)
            XCTAssertTrue(controller.intentionDraft.isEmpty)
            XCTAssertNil(NextStepSuggestion.latest(in: controller.world.history))
        }
    }

    func testStaleCloseDoneCannotAdvanceOrBridgeAReplacementSession() throws {
        try withStore { store in
            _ = try saveCloseBeatSession(to: store, recallText: "stale next step")
            let controller = makeController(store: store)

            _ = try store.update { engine in
                try engine.apply(.skip, now: start.addingTimeInterval(64))
                try engine.apply(
                    .start(intention: "replacement task"),
                    now: start.addingTimeInterval(65)
                )
            }

            controller.dismissCloseBeat()

            XCTAssertEqual(controller.world.live?.phase, .prime)
            XCTAssertEqual(controller.world.live?.intention, "replacement task")
            XCTAssertEqual(try store.load().live?.phase, .prime)
            XCTAssertTrue(controller.intentionDraft.isEmpty)
        }
    }

    private func makeRecallController(store: Store) throws -> PhoneSessionController {
        let start = Date().addingTimeInterval(-60)
        var engine = Engine()
        try engine.apply(.start(intention: "Finish the product slice"), now: start)
        try engine.apply(.skip, now: start.addingTimeInterval(1))
        try engine.apply(.capture("Check the empty state"), now: start.addingTimeInterval(10))
        try engine.apply(.capture("Write the release note"), now: start.addingTimeInterval(20))
        try engine.apply(.stopFocus, now: start.addingTimeInterval(30))
        try engine.apply(.skip, now: start.addingTimeInterval(31))
        try store.save(engine.world)
        try markRemote(engine.world, in: store)
        return makeController(store: store)
    }

    private func pausedPrimeWorld(intention: String) throws -> World {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        var engine = Engine()
        try engine.apply(.start(intention: intention), now: timestamp)
        try engine.apply(.pauseForRecovery, now: timestamp.addingTimeInterval(1))
        return engine.world
    }

    private func replaceWithPausedPrime(in store: Store) throws -> World {
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)
        return try store.update { engine in
            try engine.apply(.restart, now: timestamp)
            try engine.apply(.pauseForRecovery, now: timestamp.addingTimeInterval(1))
        }.world
    }

    @discardableResult
    private func saveCloseBeatSession(
        to store: Store,
        recallText: String,
        history: [CompletedSession] = []
    ) throws -> UUID {
        var world = World.empty
        world.history = history
        var engine = Engine(world: world)
        try engine.apply(.start(intention: "write the report"), now: start)
        try engine.apply(.skip, now: start.addingTimeInterval(1))
        try engine.apply(.stopFocus, now: start.addingTimeInterval(60))
        try engine.apply(.skip, now: start.addingTimeInterval(61))
        try engine.apply(.setRecallText(recallText), now: start.addingTimeInterval(62))
        try engine.apply(.skip, now: start.addingTimeInterval(63))
        let sessionID = try XCTUnwrap(engine.world.live?.id)
        try store.save(engine.world)
        try markRemote(engine.world, in: store)
        return sessionID
    }

    private func markRemote(_ world: World, in store: Store) throws {
        let generation = UUID()
        try WorldSyncMetadataStore(root: store.root).save(
            WorldSyncMetadata(
                generation: generation,
                remoteLiveSessionID: world.live?.id,
                base: WorldSyncSnapshot(world: world, generation: generation)
            )
        )
    }

    private func makeController(store: Store) -> PhoneSessionController {
        PhoneSessionController(
            store: store,
            attention: PhoneAttention(notificationsEnabled: false)
        )
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-phone-continuity-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }
}
