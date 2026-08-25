import XCTest

@testable import FlowmoCore

final class EngineRecoveryContractTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    func testRecoveryPauseRejectsNonRecoveryMutationsInEveryPhase() throws {
        let phases: [SessionPhase] = [.prime, .focus, .onBreak, .recall, .closeBeat]
        let rejectedEvents: [Event] = [
            .start(intention: "replacement"),
            .skip,
            .stopFocus,
            .capture("hidden mutation"),
            .setRecallText("hidden mutation"),
            .useParkedThoughtAsNext(
                sessionID: UUID(),
                capture: CaptureItem(text: "hidden mutation", createdAt: origin)
            ),
            .cancel,
            .configureFocusGuard(
                FocusGuardConfiguration(enabled: true, bundleIdentifiers: ["com.example.blocked"])),
            .setLastIntention("replacement"),
        ]

        for phase in phases {
            for event in rejectedEvents {
                var engine = try pausedEngine(in: phase)
                let pausedWorld = engine.world

                XCTAssertThrowsError(
                    try engine.apply(event, now: origin.addingTimeInterval(1_000)),
                    "phase: \(phase), event: \(event)"
                ) { error in
                    XCTAssertEqual(error as? EngineError, .recoveryPaused)
                }
                XCTAssertEqual(engine.world, pausedWorld, "phase: \(phase), event: \(event)")
            }
        }
    }

    func testRecoveryPauseKeepsSystemPauseIdempotentAndAllowsCuePreference() throws {
        var engine = try pausedEngine(in: .focus)
        let pausedLive = engine.world.live

        try engine.apply(.pauseForRecovery, now: origin.addingTimeInterval(1_000))
        XCTAssertEqual(engine.world.live, pausedLive)

        let nextCuePreference = !engine.world.config.cuesEnabled
        try engine.apply(.setCuesEnabled(nextCuePreference), now: origin.addingTimeInterval(1_001))
        XCTAssertEqual(engine.world.live, pausedLive)
        XCTAssertEqual(engine.world.config.cuesEnabled, nextCuePreference)
    }

    private func pausedEngine(in phase: SessionPhase) throws -> Engine {
        var engine = Engine()
        try engine.apply(.start(intention: "recovery contract"), now: origin)
        let pausedAt: Date

        switch phase {
        case .prime:
            pausedAt = origin.addingTimeInterval(30)
        case .focus:
            try engine.apply(.skip, now: origin)
            pausedAt = origin.addingTimeInterval(30)
        case .onBreak:
            try engine.apply(.skip, now: origin)
            try engine.apply(.stopFocus, now: origin.addingTimeInterval(300))
            pausedAt = origin.addingTimeInterval(301)
        case .recall:
            try engine.apply(.skip, now: origin)
            try engine.apply(.stopFocus, now: origin.addingTimeInterval(300))
            try engine.apply(.skip, now: origin.addingTimeInterval(301))
            pausedAt = origin.addingTimeInterval(302)
        case .closeBeat:
            try engine.apply(.skip, now: origin)
            try engine.apply(.stopFocus, now: origin.addingTimeInterval(300))
            try engine.apply(.skip, now: origin.addingTimeInterval(301))
            try engine.apply(.skip, now: origin.addingTimeInterval(302))
            pausedAt = origin.addingTimeInterval(303)
        }

        try engine.apply(.pauseForRecovery, now: pausedAt)
        return engine
    }
}
