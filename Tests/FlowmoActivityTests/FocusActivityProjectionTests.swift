import FlowmoActivity
import FlowmoCore
import Foundation
import XCTest

final class FocusActivityProjectionTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnlyUnpausedFocusProducesAClock() throws {
        var engine = Engine()
        XCTAssertNil(FocusActivityProjection(world: engine.world))
        try engine.apply(.start(intention: "private synthetic intention"), now: origin)
        XCTAssertNil(FocusActivityProjection(world: engine.world))
        try engine.apply(.skip, now: origin.addingTimeInterval(10))
        let focus = try XCTUnwrap(FocusActivityProjection(world: engine.world))
        XCTAssertEqual(focus.startedAt, origin.addingTimeInterval(10))
        XCTAssertEqual(focus.sessionID, engine.world.live?.id)
        engine.sync(now: origin.addingTimeInterval(100))
        XCTAssertEqual(FocusActivityProjection(world: engine.world), focus)
        try engine.apply(.stopFocus, now: origin.addingTimeInterval(100))
        XCTAssertNil(FocusActivityProjection(world: engine.world))
        try engine.apply(.skip, now: origin.addingTimeInterval(101))
        XCTAssertNil(FocusActivityProjection(world: engine.world))
        try engine.apply(.skip, now: origin.addingTimeInterval(102))
        XCTAssertNil(FocusActivityProjection(world: engine.world))
    }

    func testRecoveryHidesClockAndContinueUsesShiftedPersistedOrigin() throws {
        var engine = Engine()
        try engine.apply(.start(intention: "private synthetic intention"), now: origin)
        try engine.apply(.skip, now: origin)
        let sessionID = engine.world.live?.id
        try engine.apply(.pauseForRecovery, now: origin.addingTimeInterval(90))
        XCTAssertNil(FocusActivityProjection(world: engine.world))
        try engine.apply(.continue, now: origin.addingTimeInterval(150))
        let resumed = try XCTUnwrap(FocusActivityProjection(world: engine.world))
        XCTAssertEqual(resumed.sessionID, sessionID)
        XCTAssertEqual(resumed.startedAt, origin.addingTimeInterval(60))
    }

    func testClockProjectionDoesNotContainIntentionOrCapturedText() throws {
        var engine = Engine()
        try engine.apply(.start(intention: "private synthetic intention"), now: origin)
        try engine.apply(.skip, now: origin)
        let before = FocusActivityProjection(world: engine.world)
        try engine.apply(.capture("private synthetic thought"), now: origin.addingTimeInterval(1))
        engine.world.live?.intention = "different private synthetic intention"
        XCTAssertEqual(FocusActivityProjection(world: engine.world), before)
        engine.world.live?.focusStartedAt = nil
        XCTAssertEqual(FocusActivityProjection(world: engine.world)?.startedAt, origin)
    }
}
