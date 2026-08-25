import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoWindow

@MainActor
final class ContinuityControllerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testSelectedHistorySessionFillsDraftWithoutStartingOrPersisting() throws {
        try withStore { store in
            let session = CompletedSession(
                id: UUID(),
                intention: "write the report",
                focusSeconds: 600,
                breakSeconds: 120,
                captureCount: 0,
                recallText: "finish the conclusion",
                endedAt: start
            )
            var world = World.empty
            world.history = [session]
            try store.save(world)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))

            XCTAssertTrue(controller.resumeCompletedSession(session))
            XCTAssertEqual(controller.intentionDraft, "finish the conclusion")
            XCTAssertNil(controller.world.live)
            XCTAssertEqual(try store.load(), world)
        }
    }

    func testSelectedHistorySessionRequiresExplicitReplacementOfTypedDraft() throws {
        try withStore { store in
            let session = CompletedSession(
                id: UUID(),
                intention: "write the report",
                focusSeconds: 600,
                breakSeconds: 120,
                captureCount: 0,
                recallText: "finish the conclusion",
                endedAt: start
            )
            var world = World.empty
            world.history = [session]
            try store.save(world)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.intentionDraft = "keep this draft"

            XCTAssertFalse(controller.resumeCompletedSession(session))
            XCTAssertEqual(controller.intentionDraft, "keep this draft")
            XCTAssertTrue(
                controller.resumeCompletedSession(session, replacingCurrentDraft: true)
            )
            XCTAssertEqual(controller.intentionDraft, "finish the conclusion")
            XCTAssertEqual(try store.load(), world)
        }
    }

    func testPromotingParkedThoughtDuringReflectionPersistsNextStepAndKeepsCapture() throws {
        try withStore { store in
            try saveReflectionSession(to: store)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.beginMacProcessLifetime()
            XCTAssertEqual(controller.world.live?.phase, .recall)
            let capture = try XCTUnwrap(controller.world.live?.captures.first)

            XCTAssertTrue(controller.useParkedThoughtAsNext(capture))
            XCTAssertEqual(controller.recallDraft, "review the evidence")
            XCTAssertEqual(controller.world.live?.recallText, "review the evidence")
            XCTAssertEqual(controller.world.live?.captures, [capture])

            let persisted = try store.load()
            XCTAssertEqual(persisted.live?.recallText, "review the evidence")
            XCTAssertEqual(persisted.live?.captures, [capture])
        }
    }

    func testParkedPromotionPreservesTypedAndStoredRecallAndRejectsForeignCapture() throws {
        try withStore { store in
            try saveReflectionSession(to: store)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.beginMacProcessLifetime()
            XCTAssertEqual(controller.world.live?.phase, .recall)
            let capture = try XCTUnwrap(controller.world.live?.captures.first)
            let foreignCapture = CaptureItem(text: "not in this session", createdAt: start)

            XCTAssertFalse(controller.useParkedThoughtAsNext(foreignCapture))
            XCTAssertEqual(controller.world.live?.recallText, "")
            XCTAssertEqual(controller.world.live?.captures, [capture])

            controller.recallDraft = "typed next step"
            XCTAssertFalse(controller.useParkedThoughtAsNext(capture))
            XCTAssertEqual(controller.recallDraft, "typed next step")
            XCTAssertEqual(controller.world.live?.recallText, "")
            XCTAssertEqual(controller.world.live?.captures, [capture])

            controller.recallDraft = "saved next step"
            controller.persistRecall()
            XCTAssertFalse(controller.useParkedThoughtAsNext(capture))
            XCTAssertEqual(controller.recallDraft, "saved next step")
            XCTAssertEqual(controller.world.live?.recallText, "saved next step")
            XCTAssertEqual(controller.world.live?.captures, [capture])
            XCTAssertEqual(try store.load().live?.recallText, "saved next step")
        }
    }

    func testParkedPromotionDoesNotOverwriteRecallSavedByAnotherSurface() throws {
        try withStore { store in
            try saveReflectionSession(to: store)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.beginMacProcessLifetime()
            let capture = try XCTUnwrap(controller.world.live?.captures.first)

            _ = try store.update { engine in
                try engine.apply(.setRecallText("saved elsewhere"), now: start.addingTimeInterval(62))
            }

            XCTAssertFalse(controller.useParkedThoughtAsNext(capture))
            XCTAssertEqual(controller.recallDraft, "saved elsewhere")
            XCTAssertEqual(controller.world.live?.recallText, "saved elsewhere")
            XCTAssertEqual(try store.load().live?.recallText, "saved elsewhere")
            XCTAssertEqual(controller.world.live?.captures, [capture])
        }
    }

    private func saveReflectionSession(to store: Store) throws {
        var engine = Engine()
        try engine.apply(.start(intention: "write the report"), now: start)
        try engine.apply(.skip, now: start)
        try engine.apply(.capture("review the evidence"), now: start.addingTimeInterval(1))
        try engine.apply(.stopFocus, now: start.addingTimeInterval(60))
        try engine.apply(.skip, now: start.addingTimeInterval(61))
        try store.save(engine.world)
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-window-continuity-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }
}
