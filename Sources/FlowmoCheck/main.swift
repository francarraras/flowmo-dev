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

let t0 = Date(timeIntervalSince1970: 1_700_000_000)

do {
    var engine = Engine()
    try engine.apply(.start(label: "writing"), now: t0)
    Check.expect(engine.world.live?.state == .priming, "start begins priming")
    Check.expect(engine.world.live?.label == "writing", "label stored")
    Check.expect(engine.world.live?.breakRatio == 5, "default ratio")
    Check.expect(engine.status(now: t0)?.remaining == 120, "prime remaining")
} catch {
    Check.expect(false, "start begins priming threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(label: "code"), now: t0)
    engine.sync(now: t0.addingTimeInterval(120))
    Check.expect(engine.world.live?.state == .encoding, "prime expires into focus")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(180))?.elapsed ?? -1, 60, "focus elapsed after prime")
} catch {
    Check.expect(false, "prime expire threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(label: "study"), now: t0)
    try engine.apply(.skip, now: t0.addingTimeInterval(10))
    Check.expect(engine.world.live?.state == .encoding, "skip prime")
} catch {
    Check.expect(false, "skip prime threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(label: "writing"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopEncoding, now: t0.addingTimeInterval(600))
    Check.expect(engine.world.live?.state == .onBreak, "stop enters break")
    Check.expectNear(engine.world.live?.breakDuration ?? -1, 120, "600s / 5 = 120s break")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(600))?.remaining ?? -1, 120, "break remaining")
} catch {
    Check.expect(false, "stop encoding threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(label: "code"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.pause, now: t0.addingTimeInterval(90))
    Check.expect(engine.world.live?.state == .paused, "pause")
    Check.expectNear(engine.status(now: t0.addingTimeInterval(190))?.elapsed ?? -1, 90, "pause freezes elapsed")
    try engine.apply(.resume, now: t0.addingTimeInterval(190))
    Check.expectNear(engine.status(now: t0.addingTimeInterval(200))?.elapsed ?? -1, 100, "resume continues")
} catch {
    Check.expect(false, "pause/resume threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(label: "writing"), now: t0)
    var blocked = false
    do { try engine.apply(.capture("too early"), now: t0) } catch EngineError.cannotCapture { blocked = true }
    Check.expect(blocked, "no capture during prime")
    try engine.apply(.skip, now: t0)
    try engine.apply(.capture("  email the accountant  "), now: t0.addingTimeInterval(5))
    Check.expect(engine.world.live?.captures.map(\.text) == ["email the accountant"], "capture trimmed")
} catch {
    Check.expect(false, "capture threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(label: "writing"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopEncoding, now: t0.addingTimeInterval(300))
    try engine.apply(.skip, now: t0.addingTimeInterval(301))
    Check.expect(engine.world.live?.state == .recall, "skip break -> recall")
    try engine.apply(.skip, now: t0.addingTimeInterval(302))
    Check.expect(engine.world.live == nil, "skip recall finishes")
    Check.expect(engine.world.history.count == 1, "history saved")
    Check.expectNear(engine.world.history[0].focusSeconds, 300, "focus recorded")
    Check.expect(engine.world.profile.sessionCount == 1, "profile counted")
} catch {
    Check.expect(false, "full loop threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(label: "code"), now: t0)
    try engine.apply(.skip, now: t0)
    try engine.apply(.stopEncoding, now: t0.addingTimeInterval(600))
    engine.sync(now: t0.addingTimeInterval(720))
    Check.expect(engine.world.live?.state == .recall, "break expires into recall")
} catch {
    Check.expect(false, "break expire threw \(error)")
}

do {
    var engine = Engine()
    try engine.apply(.start(label: "a"), now: t0)
    var blocked = false
    do { try engine.apply(.start(label: "b"), now: t0) } catch EngineError.alreadyRunning { blocked = true }
    Check.expect(blocked, "second start rejected")
    try engine.apply(.cancel, now: t0)
    Check.expect(engine.world.live == nil, "cancel clears live")
    Check.expect(engine.world.history.count == 0, "cancel does not save")
} catch {
    Check.expect(false, "start/cancel threw \(error)")
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

do {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("flowmo-check-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Store(root: root)
    _ = try store.update { engine in
        try engine.apply(.start(label: "writing"), now: t0)
        try engine.apply(.skip, now: t0)
        try engine.apply(.capture("idea"), now: t0)
    }
    let reloaded = try store.load()
    Check.expect(reloaded.live?.state == .encoding, "store keeps focus state")
    Check.expect(reloaded.live?.label == "writing", "store keeps label")
    Check.expect(reloaded.live?.captures.map(\.text) == ["idea"], "store keeps capture")
} catch {
    Check.expect(false, "store threw \(error)")
}

if Check.failed == 0 {
    print("ok")
    exit(0)
}
print("\(Check.failed) failed")
exit(1)
