import Foundation
import FlowmoCore

public enum FlowmoCLI {
    public static let verbs: Set<String> = [
        "help", "-h", "--help",
        "start", "stop", "skip", "continue", "cancel",
        "capture", "log", "recall", "status", "live", "check",
        "pause", "resume",
    ]

    public static func isInvocation(_ args: [String]) -> Bool {
        guard let command = args.first else { return false }
        return verbs.contains(command)
    }

    public static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            let code = try run(args)
            exit(code)
        } catch let error as EngineError {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data(("Error: \(error)\n").utf8))
            exit(1)
        }
    }

    static func run(_ args: [String]) throws -> Int32 {
        guard let command = args.first else {
            print(help)
            return 0
        }

        switch command {
        case "help", "-h", "--help":
            print(help)
            return 0
        case "start":
            let intention = args.dropFirst().joined(separator: " ")
            try mutate { engine, now in
                try engine.apply(.start(intention: intention), now: now)
            }
            print("Priming.")
            return 0
        case "stop":
            try mutate { engine, now in
                try engine.apply(.stopFocus, now: now)
            }
            print("Focus stopped. Break started.")
            return 0
        case "skip":
            try mutate { engine, now in
                try engine.apply(.skip, now: now)
            }
            print(skipMessage())
            return 0
        case "continue":
            try mutate { engine, now in
                try engine.apply(.`continue`, now: now)
            }
            print("Continued.")
            return 0
        case "pause", "resume":
            FileHandle.standardError.write(Data(
                ("pause/resume are not flow controls. Quit or sleep pauses for recovery; continue resumes that phase.\n").utf8
            ))
            return 2
        case "cancel":
            try mutate { engine, now in
                try engine.apply(.cancel, now: now)
            }
            print("Session cancelled.")
            return 0
        case "capture", "log":
            let text = args.dropFirst().joined(separator: " ")
            try mutate { engine, now in
                try engine.apply(.capture(text), now: now)
            }
            print("Parked.")
            return 0
        case "recall":
            let text = args.dropFirst().joined(separator: " ")
            try mutate { engine, now in
                try engine.apply(.setRecallText(text), now: now)
            }
            print("Recall text saved.")
            return 0
        case "status":
            let json = args.contains("--json")
            return try status(json: json)
        case "live":
            return try LiveView.run()
        default:
            FileHandle.standardError.write(Data(("Unknown command: \(command)\n\n\(help)\n").utf8))
            return 2
        }
    }

    static func mutate(_ body: (inout Engine, Date) throws -> Void) throws {
        _ = try Store.default.update { engine in
            try body(&engine, Date())
        }
    }

    static func skipMessage() -> String {
        do {
            var engine = Engine(world: try Store.default.load())
            engine.sync(now: Date())
            guard let live = engine.world.live else {
                return "Idle."
            }
            switch live.phase {
            case .prime: return "Session running."
            case .focus: return "Focusing."
            case .onBreak: return "Break started."
            case .recall: return "Reflection: what did you just do?"
            case .closeBeat: return "Close beat."
            }
        } catch {
            return "Advanced."
        }
    }

    static func status(json: Bool) throws -> Int32 {
        let world: World = try Store.default.update { engine in
            engine.sync(now: Date())
        }.world

        if json {
            let payload = StatusPayload(world: world, now: Date())
            let data = try JSONEncoder.flowmo.encode(payload)
            print(String(decoding: data, as: UTF8.self))
            return 0
        }

        print(humanStatus(world, now: Date()))
        return 0
    }

    static func humanStatus(_ world: World, now: Date) -> String {
        Format.liveView(Engine.sessionStatus(world, now: now))
    }

    static let help = """
    flowmo — Mac window. Verbs are a side door to the same live session.

    (no args)                open the compact window
    live                     stay open and tick (view, not a command list)
    start [intention]
    stop
    skip
    continue                 recovery after quit/sleep
    capture <text>
    recall <text>
    cancel
    status
    status --json
    check                    core proofs
    """
}

private struct StatusPayload: Encodable {
    var running: Bool
    var phase: String?
    var paused: Bool
    var intention: String?
    var lastIntention: String
    var elapsed: TimeInterval?
    var remaining: TimeInterval?
    var focusSeconds: TimeInterval?
    var breakSeconds: TimeInterval?
    var earnedBreakSeconds: TimeInterval?
    var ratio: Double
    var captures: [String]
    var recallText: String?
    var todayFocusSeconds: TimeInterval
    var sessionCount: Int
    var cuesEnabled: Bool
    var recentFocusSeconds: [TimeInterval]
    var primeSeconds: TimeInterval
    var recallSeconds: TimeInterval

    init(world: World, now: Date) {
        let view = Engine.sessionStatus(world, now: now)
        running = view.phase != nil
        phase = view.phase?.rawValue
        paused = view.isPaused
        intention = view.phase == nil ? nil : view.intention
        lastIntention = view.lastIntention
        elapsed = view.phase == nil ? nil : view.elapsed
        remaining = view.remaining
        focusSeconds = view.phase == nil ? nil : view.focusSeconds
        breakSeconds = view.breakSeconds
        earnedBreakSeconds = view.phase == .focus ? view.earnedBreakSeconds : nil
        ratio = view.ratio
        captures = view.captures.map(\.text)
        recallText = view.recallText.isEmpty ? nil : view.recallText
        todayFocusSeconds = view.todayFocusSeconds
        sessionCount = world.profile.sessionCount
        cuesEnabled = world.config.cuesEnabled
        recentFocusSeconds = world.profile.recentFocusSeconds
        primeSeconds = world.config.primeSeconds
        recallSeconds = world.config.recallSeconds
    }
}
