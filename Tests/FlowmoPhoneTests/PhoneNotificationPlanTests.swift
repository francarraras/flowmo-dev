import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoPhone

final class PhoneNotificationPlanTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testBreakSchedulesBothEndsUsingTheLiveSessionsDurations() throws {
        var world = try breakWorld()
        world.config.recallSeconds = 999

        let plan = PhoneNotificationPlan(world: world, now: start.addingTimeInterval(50))

        XCTAssertEqual(plan.notifications.map(\.destination), [.recall, .closeBeat])
        XCTAssertEqual(plan.notifications.map(\.fireDate), dates(60, 77))
        XCTAssertEqual(Set(plan.notifications.map(\.identifier)).count, 2)
    }

    func testReturningDuringReflectionOnlySchedulesItsFutureEndWithoutWritingCatchUp() throws {
        let world = try breakWorld()

        for elapsed in [60.0, 65.0] {
            let plan = PhoneNotificationPlan(world: world, now: start.addingTimeInterval(elapsed))

            XCTAssertEqual(plan.notifications.map(\.destination), [.closeBeat])
            XCTAssertEqual(plan.notifications.map(\.fireDate), dates(77))
            XCTAssertEqual(world.live?.phase, .onBreak)
        }
        XCTAssertTrue(
            PhoneNotificationPlan(world: world, now: start.addingTimeInterval(77)).notifications.isEmpty
        )
    }

    func testEarlyReflectReplacesBothOldDeadlinesAndCloseCancelsTheChain() throws {
        var engine = Engine(world: try breakWorld())
        let original = PhoneNotificationPlan(world: engine.world, now: start.addingTimeInterval(50))
        try engine.apply(.skip, now: start.addingTimeInterval(55))

        let reflected = PhoneNotificationPlan(world: engine.world, now: start.addingTimeInterval(55))

        XCTAssertEqual(reflected.notifications.map(\.destination), [.closeBeat])
        XCTAssertEqual(reflected.notifications.map(\.fireDate), dates(72))
        XCTAssertTrue(
            original.notifications.allSatisfy {
                PhoneNotificationPlan.identifiersToCancel.contains($0.identifier)
            }
        )
        XCTAssertTrue(PhoneNotificationPlan.identifiersToCancel.contains("flowmo.timed-phase"))

        try engine.apply(.skip, now: start.addingTimeInterval(56))
        XCTAssertTrue(
            PhoneNotificationPlan(world: engine.world, now: start.addingTimeInterval(56)).notifications.isEmpty
        )
    }

    func testRecoveryCancelsEveryNoticeAndContinueMovesBothDeadlines() throws {
        var engine = Engine(world: try breakWorld())
        try engine.apply(.pauseForRecovery, now: start.addingTimeInterval(55))

        XCTAssertTrue(
            PhoneNotificationPlan(world: engine.world, now: start.addingTimeInterval(155)).notifications.isEmpty
        )

        try engine.apply(.continue, now: start.addingTimeInterval(155))
        let resumed = PhoneNotificationPlan(world: engine.world, now: start.addingTimeInterval(155))

        XCTAssertEqual(resumed.notifications.map(\.destination), [.recall, .closeBeat])
        XCTAssertEqual(resumed.notifications.map(\.fireDate), dates(160, 177))
    }

    func testPrimeSchedulesOnlyFocusAndOpenEndedFocusSchedulesNothing() throws {
        var engine = Engine()
        try engine.apply(.start(intention: "synthetic notification proof"), now: start)

        let prime = PhoneNotificationPlan(world: engine.world, now: start.addingTimeInterval(20))

        XCTAssertEqual(prime.notifications.map(\.destination), [.focus])
        XCTAssertEqual(prime.notifications.map(\.fireDate), dates(120))
        XCTAssertTrue(
            PhoneNotificationPlan(world: engine.world, now: start.addingTimeInterval(120)).notifications.isEmpty
        )
        XCTAssertTrue(
            PhoneNotificationPlan(world: engine.world, now: start.addingTimeInterval(10_000)).notifications.isEmpty
        )
        XCTAssertTrue(PhoneNotificationPlan(world: .empty, now: start).notifications.isEmpty)
    }

    private func breakWorld() throws -> World {
        var world = World.empty
        world.config.recallSeconds = 17
        var engine = Engine(world: world)
        try engine.apply(.start(intention: "synthetic notification proof"), now: start)
        try engine.apply(.skip, now: start)
        try engine.apply(.stopFocus, now: start.addingTimeInterval(50))
        return engine.world
    }

    private func dates(_ intervals: TimeInterval...) -> [Date] {
        intervals.map { start.addingTimeInterval($0) }
    }
}
