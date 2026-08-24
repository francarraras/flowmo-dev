import XCTest

@testable import FlowmoCore

final class EngineCompletionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testCloseBeatDismissalRecordsCompletionExactlyOnce() throws {
        var engine = try closeBeatEngine()

        XCTAssertEqual(engine.world.live?.phase, .closeBeat)
        XCTAssertTrue(engine.world.history.isEmpty)
        XCTAssertEqual(engine.world.profile.sessionCount, 0)

        try engine.apply(.skip, now: start.addingTimeInterval(604))

        XCTAssertNil(engine.world.live)
        XCTAssertEqual(engine.world.history.count, 1)
        XCTAssertEqual(engine.world.history.first?.focusSeconds, 600)
        XCTAssertEqual(engine.world.profile.sessionCount, 1)
        XCTAssertEqual(engine.world.profile.totalFocusSeconds, 600)

        XCTAssertThrowsError(try engine.apply(.skip, now: start.addingTimeInterval(605))) { error in
            XCTAssertEqual(error as? EngineError, .nothingRunning)
        }
        XCTAssertEqual(engine.world.history.count, 1)
        XCTAssertEqual(engine.world.profile.sessionCount, 1)
    }

    func testRestartingRecoveryPausedCloseBeatDiscardsFrozenSession() throws {
        var engine = try closeBeatEngine()
        let discardedID = try XCTUnwrap(engine.world.live?.id)
        let originalProfile = engine.world.profile

        try engine.apply(.pauseForRecovery, now: start.addingTimeInterval(700))
        try engine.apply(.restart, now: start.addingTimeInterval(800))

        XCTAssertEqual(engine.world.live?.phase, .prime)
        XCTAssertEqual(engine.world.live?.intention, "writing")
        XCTAssertNotEqual(engine.world.live?.id, discardedID)
        XCTAssertTrue(engine.world.history.isEmpty)
        XCTAssertEqual(engine.world.profile, originalProfile)
    }

    func testCancellingCloseBeatDiscardsWithoutRecordingCompletion() throws {
        var engine = try closeBeatEngine()
        let originalProfile = engine.world.profile

        try engine.apply(.cancel, now: start.addingTimeInterval(604))

        XCTAssertNil(engine.world.live)
        XCTAssertTrue(engine.world.history.isEmpty)
        XCTAssertEqual(engine.world.profile, originalProfile)
    }

    func testCompletionPreservesRatioAndLegacySamplesWhileClearingMovementNote() throws {
        var profile = Profile.default
        profile.breakRatio = 4.75
        profile.recentFocusSeconds = [3_000, 3_000]
        profile.lastNote = "Legacy ratio movement note."
        var engine = try closeBeatEngine(profile: profile)

        try engine.apply(.skip, now: start.addingTimeInterval(604))

        XCTAssertEqual(engine.world.profile.breakRatio, 4.75)
        XCTAssertEqual(engine.world.profile.recentFocusSeconds, [3_000, 3_000])
        XCTAssertNil(engine.world.profile.lastNote)
        XCTAssertEqual(engine.world.profile.sessionCount, 1)
        XCTAssertEqual(engine.world.profile.totalFocusSeconds, 600)
    }

    private func closeBeatEngine(profile: Profile = .default) throws -> Engine {
        var world = World.empty
        world.profile = profile
        var engine = Engine(world: world)
        try engine.apply(.start(intention: "writing"), now: start)
        try engine.apply(.skip, now: start)
        try engine.apply(.stopFocus, now: start.addingTimeInterval(600))
        try engine.apply(.skip, now: start.addingTimeInterval(601))
        try engine.apply(.setRecallText("shipped the slice"), now: start.addingTimeInterval(602))
        try engine.apply(.skip, now: start.addingTimeInterval(603))
        return engine
    }
}
