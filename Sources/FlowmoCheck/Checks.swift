import Foundation
import FlowmoCore

enum Check {
    nonisolated(unsafe) static var failed = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition { return }
        failed += 1
        FileHandle.standardError.write(Data(("FAIL  \(message)\n").utf8))
    }

    static func expectEqual<T: Equatable>(_ got: T, _ want: T, _ message: String) {
        expect(got == want, "\(message)  got \(got) want \(want)")
    }

    static func expectNear(_ got: TimeInterval, _ want: TimeInterval, _ message: String) {
        expect(abs(got - want) < 0.01, "\(message)  got \(got) want \(want)")
    }
}

public func runFlowmoChecks() -> Int32 {
    Check.failed = 0
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func loopToCloseBeat() throws -> Engine {
    var engine = Engine()
    try engine.apply(.start(intention: "writing"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(600))
    try engine.apply(.skip, now: t0.addingTimeInterval(601))
    try engine.apply(.setRecallText("shipped the slice"), now: t0.addingTimeInterval(602))
    try engine.apply(.skip, now: t0.addingTimeInterval(603))
    return engine
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "writing"), now: t0)
    Check.expect(engine.world.live?.phase == .prime, "start begins prime")
    Check.expect(engine.world.live?.intention == "writing", "intention stored")
    Check.expect(engine.world.profile.lastIntention == "writing", "lastIntention stored")
    Check.expectEqual(engine.world.live?.recallDuration ?? -1, 180, "reflection is 3:00")
    Check.expect(engine.world.live?.breakRatio == 5, "default ratio")
    Check.expectNear(engine.status(now: t0).remaining ?? -1, 120, "prime remaining")
    Check.expect(engine.status(now: t0).phase == .prime, "status phase prime")
} catch {
    Check.expect(false, "start begins prime threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: ""), now: t0)
    engine.world.live = nil
    engine.world.profile.lastIntention = "kept line"
    try engine.apply(.start(intention: "  "), now: t0.addingTimeInterval(1))
    Check.expectEqual(engine.world.live?.intention ?? "", "kept line", "empty start keeps last intention")
} catch {
    Check.expect(false, "keep last intention threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "code"), now: t0)
    engine.sync(now: t0.addingTimeInterval(120))
    Check.expect(engine.world.live?.phase == .focus, "prime expires into focus")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(180)).elapsed, 60, "focus elapsed after prime")
    Check.expect(engine.status(now: t0.addingTimeInterval(180)).remaining == nil, "focus has no remaining")
} catch {
    Check.expect(false, "prime expire threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "study"), now: t0)
    try engine.apply(.skip, now: t0.addingTimeInterval(10))
    Check.expect(engine.world.live?.phase == .focus, "skip prime")
} catch {
    Check.expect(false, "skip prime threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "writing"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(600))
    Check.expect(engine.world.live?.phase == .onBreak, "stop enters break")
    Check.expectNear(engine.world.live?.breakDuration ?? -1, 120, "600s / 5 = 120s break")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(600)).remaining ?? -1, 120, "break remaining")
} catch {
    Check.expect(false, "stop focus threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "writing"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.skip, now: t0.addingTimeInterval(90))
    Check.expect(engine.world.live?.phase == .onBreak, "skip during focus is stop")
    Check.expectNear(engine.world.live?.breakDuration ?? -1, 18, "90s / 5 = 18s break")
} catch {
    Check.expect(false, "skip=stop threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "code"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(90))
    Check.expect(engine.world.live?.isPaused == true, "pause recovery")
    Check.expect(engine.world.live?.phase == .focus, "pause keeps focus")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(190)).elapsed, 90, "pause freezes elapsed")
    try engine.apply(.`continue`, now: t0.addingTimeInterval(190))
    Check.expect(engine.world.live?.phase == .focus, "continue stays focus")
    Check.expect(engine.world.live?.isPaused == false, "continue clears pause")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(200)).elapsed, 100, "resume continues elapsed")
} catch {
    Check.expect(false, "focus pause/continue threw \(error)")
}


do {
    var engine = Engine()
    try engine.apply(.start(intention: "rewrite"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.capture("parked"), now: t0.addingTimeInterval(20))
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(90))
    let pausedID = engine.world.live?.id
    try engine.apply(.restart, now: t0.addingTimeInterval(190))
    Check.expect(engine.world.live?.phase == .prime, "restart begins prime")
    Check.expectEqual(engine.world.live?.intention ?? "", "rewrite", "restart keeps intention")
    Check.expect(engine.world.live?.isPaused == false, "restart is live")
    Check.expect(engine.world.live?.id != pausedID, "restart is a new session")
    Check.expect(engine.world.live?.captures.isEmpty == true, "restart drops parked lines")
    Check.expect(engine.world.history.isEmpty, "restart does not record")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(190)).elapsed, 0, "restart clocks are new")
    do {
        try engine.apply(.restart, now: t0.addingTimeInterval(191))
        Check.expect(false, "restart while live should fail")
    } catch let error as EngineError {
        Check.expect(error == .notPaused, "restart while live is notPaused")
    }
    engine.world.live = nil
    do {
        try engine.apply(.restart, now: t0.addingTimeInterval(192))
        Check.expect(false, "restart while idle should fail")
    } catch let error as EngineError {
        Check.expect(error == .nothingRunning, "restart while idle is nothingRunning")
    }
} catch {
    Check.expect(false, "focus pause/restart threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "code"), now: t0)
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(40))
    Check.expect(engine.world.live?.phase == .prime, "pause during prime")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(400)).remaining ?? -1, 80, "prime remaining frozen")
    try engine.apply(.`continue`, now: t0.addingTimeInterval(400))
    Check.expect(engine.world.live?.phase == .prime, "continue stays prime")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(400)).remaining ?? -1, 80, "continue same remaining")
    engine.sync(now: t0.addingTimeInterval(480))
    Check.expect(engine.world.live?.phase == .focus, "prime finishes after remaining")
} catch {
    Check.expect(false, "prime pause/continue threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "code"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(600))
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(630))
    Check.expect(engine.world.live?.phase == .onBreak, "pause during break")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(900)).remaining ?? -1, 90, "break remaining frozen")
    try engine.apply(.`continue`, now: t0.addingTimeInterval(900))
    Check.expect(engine.world.live?.phase == .onBreak, "continue stays break")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(900)).remaining ?? -1, 90, "break remaining after continue")
} catch {
    Check.expect(false, "break pause/continue threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "code"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(100))
    try engine.apply(.skip, now: t0.addingTimeInterval(101))
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(151))
    Check.expect(engine.world.live?.phase == .recall, "pause during recall")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(800)).remaining ?? -1, 130, "recall remaining frozen")
    try engine.apply(.`continue`, now: t0.addingTimeInterval(800))
    Check.expect(engine.world.live?.phase == .recall, "continue stays recall")
} catch {
    Check.expect(false, "recall pause/continue threw \(error)")
}

do {
    var engine = try loopToCloseBeat()
    Check.expect(engine.world.live?.phase == .closeBeat, "recall skip enters close beat")
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(700))
    Check.expect(engine.world.live?.phase == .closeBeat, "pause during close beat")
    try engine.apply(.`continue`, now: t0.addingTimeInterval(800))
    Check.expect(engine.world.live?.phase == .closeBeat, "continue stays close beat")
    Check.expect(engine.world.live?.isPaused == false, "close beat continue clears pause")
} catch {
    Check.expect(false, "close beat pause/continue threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "writing"), now: t0)
    var blocked = false
    do { try engine.apply(.capture("too early"), now: t0) } catch EngineError.cannotCapture { blocked = true }
    Check.expect(blocked, "no capture during prime")
    try engine.apply(.skip, now: t0)
    try engine.apply(.capture("  email the accountant  "), now: t0.addingTimeInterval(5))
    Check.expect(engine.world.live?.captures.map(\.text) == ["email the accountant"], "capture trimmed")
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(6))
    try engine.apply(.capture("while frozen"), now: t0.addingTimeInterval(7))
    Check.expect(engine.world.live?.captures.map(\.text) == ["email the accountant", "while frozen"], "capture while paused focus")
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(8))
    try engine.apply(.skip, now: t0.addingTimeInterval(9))
    try engine.apply(.skip, now: t0.addingTimeInterval(10))
    Check.expect(engine.world.history[0].captures.map(\.text) == ["email the accountant", "while frozen"], "history keeps parked lines")
} catch {
    Check.expect(false, "capture threw \(error)")
}

do {
    var engine = try loopToCloseBeat()
    Check.expect(engine.world.live?.phase == .closeBeat, "close beat after recall")
    Check.expectEqual(engine.world.live?.recallText ?? "", "shipped the slice", "recall text on snapshot")
    Check.expect(engine.world.history.count == 1, "history recorded at close beat")
    Check.expectNear(engine.world.history[0].focusSeconds, 600, "focus recorded")
    engine.sync(now: t0.addingTimeInterval(50_000))
    Check.expect(engine.world.live?.phase == .closeBeat, "close beat does not auto-idle")
    try engine.apply(.skip, now: t0.addingTimeInterval(50_001))
    Check.expect(engine.world.live == nil, "skip dismisses close beat")
    Check.expect(engine.world.history.count == 1, "dismiss does not double-record")
} catch {
    Check.expect(false, "close beat threw \(error)")
}

do {
    let olderID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let earlierTieID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let laterTieID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    func completed(_ id: UUID, endedAt: Date) -> CompletedSession {
        CompletedSession(
            id: id,
            intention: id.uuidString,
            focusSeconds: 60,
            breakSeconds: 12,
            captureCount: 0,
            recallText: nil,
            endedAt: endedAt
        )
    }
    let sameNewerDate = t0.addingTimeInterval(60)
    let ordered = HistoryOrder.newestFirst([
        completed(olderID, endedAt: t0),
        completed(laterTieID, endedAt: sameNewerDate),
        completed(earlierTieID, endedAt: sameNewerDate),
    ])
    Check.expectEqual(
        ordered.map(\.id),
        [earlierTieID, laterTieID, olderID],
        "history sorts newest first with stable UUID ties"
    )
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "code"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(600))
    engine.sync(now: t0.addingTimeInterval(720))
    Check.expect(engine.world.live?.phase == .recall, "break expires into recall")
    engine.sync(now: t0.addingTimeInterval(720 + 180))
    Check.expect(engine.world.live?.phase == .closeBeat, "recall expires into close beat")
} catch {
    Check.expect(false, "timed expire threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "late prime"), now: t0)
    engine.sync(now: t0.addingTimeInterval(180))
    Check.expect(engine.world.live?.phase == .focus, "late prime catch-up enters focus")
    Check.expectEqual(engine.world.live?.focusStartedAt, t0.addingTimeInterval(120), "late prime preserves deadline")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(180)).elapsed, 60, "late prime preserves focus elapsed")
} catch {
    Check.expect(false, "late prime catch-up threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "late break"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(600))
    engine.sync(now: t0.addingTimeInterval(901))
    Check.expect(engine.world.live?.phase == .closeBeat, "one sync catches up break and recall")
    Check.expectEqual(engine.world.live?.phaseStartedAt, t0.addingTimeInterval(900), "catch-up close beat uses recall deadline")
    Check.expect(engine.world.history.count == 1, "catch-up records completion once")
    engine.sync(now: t0.addingTimeInterval(2_000))
    Check.expect(engine.world.history.count == 1, "later sync does not double-record catch-up")
} catch {
    Check.expect(false, "multi-phase catch-up threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "stale skip"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(600))
    try engine.apply(.skip, now: t0.addingTimeInterval(721))
    Check.expect(engine.world.live?.phase == .recall, "stale break skip does not skip recall")
    Check.expectEqual(engine.world.live?.phaseStartedAt, t0.addingTimeInterval(720), "stale skip keeps automatic boundary")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(721)).remaining ?? -1, 179, "stale skip leaves recall running")
    Check.expect(engine.world.history.isEmpty, "stale skip does not complete session")
} catch {
    Check.expect(false, "stale skip catch-up threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "a"), now: t0)
    var blocked = false
    do { try engine.apply(.start(intention: "b"), now: t0) } catch EngineError.alreadyRunning { blocked = true }
    Check.expect(blocked, "second start rejected")
    try engine.apply(.cancel, now: t0)
    Check.expect(engine.world.live == nil, "cancel clears live")
    Check.expect(engine.world.history.count == 0, "cancel during prime does not save")
} catch {
    Check.expect(false, "start/cancel threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "code"), now: t0)
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(150))
    Check.expect(engine.world.live?.phase == .focus, "quit after prime timeout pauses in focus")
    Check.expect(engine.world.live?.isPaused == true, "recovery pause set")
} catch {
    Check.expect(false, "pause after prime timeout threw \(error)")
}

do {
    var engine = Engine()
    engine.sync(now: t0)
    Check.expect(engine.status(now: t0).isIdle, "idle status")
    Check.expectEqual(engine.status(now: t0).elapsed, 0, "idle clock 00:00")
}

do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let start = calendar.startOfDay(for: now)
    var engine = Engine()
    engine.world.history = [
        CompletedSession(
            id: UUID(),
            intention: "yesterday",
            focusSeconds: 1_000,
            breakSeconds: 200,
            captureCount: 0,
            recallText: nil,
            endedAt: start.addingTimeInterval(-60)
        ),
        CompletedSession(
            id: UUID(),
            intention: "today",
            focusSeconds: 180,
            breakSeconds: 36,
            captureCount: 0,
            recallText: nil,
            endedAt: start.addingTimeInterval(120)
        ),
    ]
    Check.expectNear(engine.status(now: now, calendar: calendar).todayFocusSeconds, 180, "today total uses local midnight")
}

var longProfile = Profile.default
for _ in 0..<3 {
    longProfile = ProfileLearner.apply(longProfile, focusSeconds: 50 * 60)
}
Check.expectNear(longProfile.breakRatio, 4.75, "three long sessions lengthen next break")
Check.expect(longProfile.lastNote != nil, "learning note set")

var shortProfile = Profile.default
for _ in 0..<3 {
    shortProfile = ProfileLearner.apply(shortProfile, focusSeconds: 10 * 60)
}
Check.expectNear(shortProfile.breakRatio, 5.25, "three short sessions shorten next break")

var floorProfile = Profile.default
floorProfile.breakRatio = 3
for _ in 0..<3 {
    floorProfile = ProfileLearner.apply(floorProfile, focusSeconds: 50 * 60)
}
Check.expectNear(floorProfile.breakRatio, 3, "ratio floor 3")

var ceilingProfile = Profile.default
ceilingProfile.breakRatio = 8
for _ in 0..<3 {
    ceilingProfile = ProfileLearner.apply(ceilingProfile, focusSeconds: 10 * 60)
}
Check.expectNear(ceilingProfile.breakRatio, 8, "ratio ceiling 8")

var mixed = Profile.default
mixed = ProfileLearner.apply(mixed, focusSeconds: 50 * 60)
mixed = ProfileLearner.apply(mixed, focusSeconds: 10 * 60)
mixed = ProfileLearner.apply(mixed, focusSeconds: 50 * 60)
Check.expectNear(mixed.breakRatio, 5, "mixed last-3 leaves ratio")

do {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("flowmo-check-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Store(root: root)
    _ = try store.update { engine in
        try engine.apply(.start(intention: "writing"), now: t0)
        try engine.apply(.skip, now: t0)
        try engine.apply(.capture("idea"), now: t0)
        try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(5))
    }
    let reloaded = try store.load()
    Check.expect(reloaded.live?.phase == .focus, "store keeps focus")
    Check.expect(reloaded.live?.intention == "writing", "store keeps intention")
    Check.expect(reloaded.profile.lastIntention == "writing", "store keeps lastIntention")
    Check.expect(reloaded.live?.captures.map(\.text) == ["idea"], "store keeps capture")
    Check.expect(reloaded.live?.isPaused == true, "store keeps recovery pause")
    Check.expect(FileManager.default.fileExists(atPath: store.worldURL.path), "world.json path")
} catch {
    Check.expect(false, "store threw \(error)")
}

Check.expectEqual(Format.clock(0.4), "00:00", "elapsed rounds 0.4s down")
Check.expectEqual(Format.clock(0.6), "00:01", "elapsed rounds 0.6s up")
Check.expectEqual(Format.remainingClock(0), "00:00", "remaining zero")
Check.expectEqual(Format.remainingClock(0.2), "00:01", "remaining 0.2s still shows a second")
Check.expectEqual(Format.remainingClock(119.1), "02:00", "remaining 119.1s ceils to 2:00")
Check.expectEqual(Format.earned(90), "1.5m earned", "earned copy")
Check.expectEqual(Format.minutes(0.2), "0s", "sub-second earned still formats as 0s")
Check.expectEqual(Format.minutes(1), "1s", "1s earned is visible")


do {
    let json = Data("""
    {"primeSeconds":120,"recallSeconds":300,"defaultBreakRatio":5}
    """.utf8)
    let config = try JSONDecoder.flowmo.decode(Config.self, from: json)
    Check.expect(config.focusGuard == .default, "legacy config has guard off")
    Check.expect(config.focusGuard.bundleIdentifiers.isEmpty, "legacy guard list empty")
} catch {
    Check.expect(false, "legacy config decode threw \(error)")
}

do {
    let live = SessionSnapshot(
        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        intention: "x",
        phase: .recall,
        breakRatio: 5,
        startedAt: t0,
        phaseStartedAt: t0,
        focusStartedAt: t0,
        focusEndedAt: t0,
        breakStartedAt: t0,
        breakDuration: 12,
        captures: [],
        primeDuration: 120,
        recallDuration: 300
    )
    let decoded = try JSONDecoder.flowmo.decode(SessionSnapshot.self, from: try JSONEncoder.flowmo.encode(live))
    Check.expectEqual(decoded.recallDuration, 180, "legacy live reflection is 3:00")
} catch {
    Check.expect(false, "legacy live snapshot decode threw \(error)")
}

do {
    let json = Data("""
    {"id":"11111111-1111-1111-1111-111111111111","intention":"x","focusSeconds":60,"breakSeconds":12,"captureCount":2,"endedAt":"2024-01-01T00:00:00.000Z"}
    """.utf8)
    let session = try JSONDecoder.flowmo.decode(CompletedSession.self, from: json)
    Check.expect(session.captures.isEmpty, "legacy history has no parked texts")
    Check.expect(session.captureCount == 2, "legacy history keeps parked count")
} catch {
    Check.expect(false, "legacy history decode threw \(error)")
}

Check.expectEqual(
    FocusGuard.normalize(["  com.apple.Safari ", "com.apple.Safari", "app.flowmo.mac", "", "com.apple.finder", "com.apple.Mail"]),
    ["com.apple.Mail", "com.apple.Safari"],
    "normalize sorts, uniques, drops forbidden"
)

do {
    var engine = Engine()
    try engine.apply(.configureFocusGuard(FocusGuardConfiguration(enabled: true, bundleIdentifiers: ["com.apple.Safari"])), now: t0)
    Check.expect(engine.world.config.focusGuard.enabled, "idle can set guard")
    Check.expectEqual(engine.world.config.focusGuard.bundleIdentifiers, ["com.apple.Safari"], "guard ids stored")
    try engine.apply(.start(intention: "x"), now: t0)
    var blocked = false
    do {
        try engine.apply(.configureFocusGuard(FocusGuardConfiguration(enabled: false, bundleIdentifiers: [])), now: t0)
    } catch EngineError.notIdle {
        blocked = true
    }
    Check.expect(blocked, "guard config idle-only")
    Check.expect(FocusGuard.demand(world: engine.world) == .inactive, "prime is not guarded")
    try engine.apply(.skip, now: t0)
    if case .active(_, let ids) = FocusGuard.demand(world: engine.world) {
        Check.expect(ids == ["com.apple.Safari"], "focus demand active")
    } else {
        Check.expect(false, "focus demand should be active")
    }
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(1))
    Check.expect(FocusGuard.demand(world: engine.world) == .inactive, "paused focus not guarded")
    try engine.apply(.`continue`, now: t0.addingTimeInterval(2))
    Check.expect(FocusGuard.demand(world: engine.world) != .inactive, "continue restores demand")
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(3))
    Check.expect(FocusGuard.demand(world: engine.world) == .inactive, "break not guarded")
} catch {
    Check.expect(false, "guard demand threw \(error)")
}

do {
    var runtime = FocusGuardRuntime()
    let sid = UUID()
    runtime.setDemand(.active(sessionID: sid, bundleIdentifiers: ["com.apple.Safari"]))
    Check.expectEqual(
        runtime.activated(bundleID: "com.apple.Mail", processID: 1, displayName: "Mail", isSelf: false),
        .ignore,
        "unselected app ignored"
    )
    Check.expectEqual(
        runtime.activated(bundleID: "com.apple.Safari", processID: 42, displayName: "Safari", isSelf: true),
        .ignore,
        "self ignored"
    )
    Check.expectEqual(
        runtime.activated(bundleID: "com.apple.Safari", processID: 42, displayName: "Safari", isSelf: false),
        .intercept,
        "selected app intercepted"
    )
    Check.expect(runtime.interception?.processIdentifier == 42, "interception stored")
    runtime.allowOnce()
    Check.expect(runtime.interception == nil, "open once clears intercept")
    Check.expectEqual(
        runtime.activated(bundleID: "com.apple.Safari", processID: 42, displayName: "Safari", isSelf: false),
        .allowedOnce,
        "same pid allowed once"
    )
    runtime.deactivated(processID: 42)
    Check.expectEqual(
        runtime.activated(bundleID: "com.apple.Safari", processID: 42, displayName: "Safari", isSelf: false),
        .intercept,
        "after deactivate, next activation intercepted"
    )
    runtime.setDemand(.inactive)
    Check.expect(runtime.interception == nil, "inactive clears intercept")
    Check.expectEqual(
        runtime.activated(bundleID: "com.apple.Safari", processID: 42, displayName: "Safari", isSelf: false),
        .ignore,
        "inactive ignores"
    )
}

do {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("flowmo-guard-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Store(root: root)
    _ = try store.update { engine in
        try engine.apply(.configureFocusGuard(FocusGuardConfiguration(enabled: true, bundleIdentifiers: ["com.apple.Safari"])), now: t0)
    }
    let loaded = try store.load()
    Check.expect(loaded.config.focusGuard.enabled, "store keeps guard on")
    Check.expectEqual(loaded.config.focusGuard.bundleIdentifiers, ["com.apple.Safari"], "store keeps guard ids")
} catch {
    Check.expect(false, "guard store threw \(error)")
}


do {
    var engine = Engine()
    Check.expectEqual(Format.glance(engine.status(now: t0)), "Flowmo", "idle glance")
    try engine.apply(.start(intention: "x"), now: t0)
    Check.expectEqual(Format.glance(engine.status(now: t0)), "02:00", "prime glance remaining")
    try engine.apply(.skip, now: t0)
    Check.expectEqual(Format.glance(engine.status(now: t0.addingTimeInterval(65))), "01:05", "focus glance elapsed")
    try engine.apply(.pauseForRecovery, now: t0.addingTimeInterval(65))
    Check.expectEqual(Format.glance(engine.status(now: t0.addingTimeInterval(200))), "· 01:05", "paused glance frozen")
} catch {
    Check.expect(false, "glance threw \(error)")
}


do {
    var engine = Engine()
    Check.expect(Format.liveView(engine.status(now: t0)).contains("idle"), "live view idle")
    try engine.apply(.start(intention: "x"), now: t0)
    Check.expect(Format.liveView(engine.status(now: t0)).contains("prime"), "live view prime")
    Check.expect(Format.liveView(engine.status(now: t0)).contains("02:00 remaining"), "live view remaining")
    try engine.apply(.skip, now: t0)
    let focus = Format.liveView(engine.status(now: t0.addingTimeInterval(65)))
    Check.expect(focus.contains("focus"), "live view focus")
    Check.expect(focus.contains("01:05"), "live view elapsed")
} catch {
    Check.expect(false, "live view threw \(error)")
}


do {
    Check.expect(Config.default.cuesEnabled, "cues on by default")
    var engine = Engine()
    try engine.apply(.setCuesEnabled(false), now: t0)
    Check.expect(!engine.world.config.cuesEnabled, "mute persists on engine")
    try engine.apply(.start(intention: "x"), now: t0)
    try engine.apply(.setCuesEnabled(true), now: t0)
    Check.expect(engine.world.config.cuesEnabled, "unmute during prime")
    try engine.apply(.skip, now: t0)
    Check.expect(engine.world.live?.phase == .focus, "mute does not change phase")
} catch {
    Check.expect(false, "cues threw \(error)")
}

do {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("flowmo-cues-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Store(root: root)
    _ = try store.update { engine in
        try engine.apply(.setCuesEnabled(false), now: t0)
    }
    let loaded = try store.load()
    Check.expect(!loaded.config.cuesEnabled, "store keeps mute")
    Check.expect(AttentionCue.shouldPlay(from: .prime, to: .focus), "cue rule independent of mute")
} catch {
    Check.expect(false, "cues store threw \(error)")
}


do {
    var engine = Engine()
    Check.expect(TimedNotice.remainingToSchedule(engine.status(now: t0)) == nil, "idle has no timed notice")
    try engine.apply(.start(intention: "x"), now: t0)
    Check.expectNear(TimedNotice.remainingToSchedule(engine.status(now: t0)) ?? -1, 120, "prime schedules remaining")
    try engine.apply(.pauseForRecovery, now: t0)
    Check.expect(TimedNotice.remainingToSchedule(engine.status(now: t0)) == nil, "paused does not schedule")
    try engine.apply(.`continue`, now: t0)
    try engine.apply(.skip, now: t0)
    Check.expect(TimedNotice.remainingToSchedule(engine.status(now: t0)) == nil, "focus has no end notice")
    try engine.apply(.stopFocus, now: t0.addingTimeInterval(50))
    Check.expectNear(TimedNotice.remainingToSchedule(engine.status(now: t0.addingTimeInterval(50))) ?? -1, 10, "break schedules remaining")
    try engine.apply(.skip, now: t0.addingTimeInterval(51))
    Check.expectNear(TimedNotice.remainingToSchedule(engine.status(now: t0.addingTimeInterval(51))) ?? -1, 180, "skip break schedules reflection")
} catch {
    Check.expect(false, "timed notice threw \(error)")
}


do {
    var engine = Engine()
    try engine.apply(.start(intention: "x"), now: t0)
    try engine.apply(.skip, now: t0)
    Check.expect(engine.world.live?.isPaused == false, "focus unpaused")
    engine.pauseUnpausedLiveOnProcessStart(now: t0.addingTimeInterval(10))
    Check.expect(engine.world.live?.isPaused == true, "process start pauses live")
    Check.expect(engine.world.live?.phase == .focus, "process start keeps phase")
    engine.pauseUnpausedLiveOnProcessStart(now: t0.addingTimeInterval(20))
    Check.expect(engine.world.live?.isPaused == true, "already paused stays paused")
} catch {
    Check.expect(false, "process start pause threw \(error)")
}

do {
    let fm = FileManager.default
    let old = fm.temporaryDirectory.appendingPathComponent("flowmo-mig-old-\(UUID().uuidString)", isDirectory: true)
    let neu = fm.temporaryDirectory.appendingPathComponent("flowmo-mig-new-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fm.removeItem(at: old)
        try? fm.removeItem(at: neu)
    }
    let source = Store(root: old)
    _ = try source.update { engine in
        try engine.apply(.setCuesEnabled(false), now: t0)
    }
    try Store.migrateWorld(from: old, to: neu)
    let loaded = try Store(root: neu).load()
    Check.expect(!loaded.config.cuesEnabled, "migrate copies world")
    _ = try source.update { engine in
        try engine.apply(.setCuesEnabled(true), now: t0)
    }
    try Store.migrateWorld(from: old, to: neu)
    let again = try Store(root: neu).load()
    Check.expect(!again.config.cuesEnabled, "migrate does not overwrite")
    try Data("broken".utf8).write(to: Store(root: neu).worldURL, options: .atomic)
    try Store.migrateWorld(from: old, to: neu)
    let repaired = try Store(root: neu).load()
    Check.expect(repaired.config.cuesEnabled, "migrate repairs corrupt destination")
} catch {
    Check.expect(false, "migrate threw \(error)")
}


do {
    Check.expect(ClockMarks.crossing(from: 299, to: 300) == 5, "cross 5:00")
    Check.expect(ClockMarks.crossing(from: 300, to: 301) == nil, "no second fire at 5:01")
    Check.expect(ClockMarks.crossing(from: 599, to: 600) == 10, "cross 10:00")
    Check.expect(ClockMarks.crossing(from: 899, to: 900) == 15, "cross 15:00")
    Check.expect(ClockMarks.crossing(from: 1799, to: 1800) == 30, "cross 30:00")
    Check.expect(ClockMarks.crossing(from: 2699, to: 2700) == 45, "cross 45:00")
    Check.expect(ClockMarks.crossing(from: 3599, to: 3600) == 60, "cross 60:00")
    Check.expect(ClockMarks.crossing(from: 290, to: 910) == 15, "jump keeps the highest mark")
    Check.expect(ClockMarks.crossing(from: 720, to: 720) == nil, "restore mid-mark is quiet")
    Check.expect(ClockMarks.crossing(from: 400, to: 200) == nil, "time going backwards is quiet")
    Check.expectEqual(Format.remainingSeconds(10.0), 10, "race window opens at 10.0")
    Check.expectEqual(Format.remainingSeconds(9.2), 10, "remaining clock holds the second")
    Check.expectEqual(Format.remainingSeconds(0), 0, "remaining zero")
}

do {
    var engine = Engine()
    try engine.apply(.start(intention: "old line"), now: t0)
    engine.world.live = nil
    try engine.apply(.setLastIntention(""), now: t0.addingTimeInterval(1))
    Check.expectEqual(engine.world.profile.lastIntention, "", "clear last intention")
    do {
        try engine.apply(.start(intention: "busy"), now: t0.addingTimeInterval(2))
        try engine.apply(.setLastIntention(""), now: t0.addingTimeInterval(3))
        Check.expect(false, "clear while running should fail")
    } catch let error as EngineError {
        Check.expect(error == .notIdle, "clear while running is notIdle")
    }
} catch {
    Check.expect(false, "setLastIntention threw \(error)")
}

    if Check.failed == 0 {
        print("ok")
        return 0
    }
    print("\(Check.failed) failed")
    return 1
}
