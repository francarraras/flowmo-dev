import Foundation
import FlowmoCore

enum CLI {
    static func main() {
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
            let label = args.dropFirst().joined(separator: " ")
            try mutate { engine, now in
                try engine.apply(.start(label: label), now: now)
            }
            print("Priming. Get still, then go.")
            return 0
        case "stop":
            try mutate { engine, now in
                try engine.apply(.stopEncoding, now: now)
            }
            print("Focus stopped. Break started.")
            return 0
        case "pause":
            try mutate { engine, now in
                try engine.apply(.pause, now: now)
            }
            print("Paused.")
            return 0
        case "resume":
            try mutate { engine, now in
                try engine.apply(.resume, now: now)
            }
            print("Back in focus.")
            return 0
        case "skip":
            try mutate { engine, now in
                try engine.apply(.skip, now: now)
            }
            print(skipMessage())
            return 0
        case "cancel":
            try mutate { engine, now in
                try engine.apply(.cancel, now: now)
            }
            print("Session cancelled. Nothing saved.")
            return 0
        case "capture", "log":
            let text = args.dropFirst().joined(separator: " ")
            try mutate { engine, now in
                try engine.apply(.capture(text), now: now)
            }
            print("Parked.")
            return 0
        case "status":
            let json = args.contains("--json")
            return try status(json: json)
        default:
            FileHandle.standardError.write(Data(("Unknown command: \(command)\n\n\(help)\n").utf8))
            return 2
        }
    }

    static func mutate(_ body: (inout Engine, Date) throws -> Void) throws {
        _ = try Store.default.update { engine in
            let now = Date()
            engine.sync(now: now)
            try body(&engine, now)
            engine.sync(now: now)
        }
    }

    static func skipMessage() -> String {
        do {
            var engine = Engine(world: try Store.default.load())
            engine.sync(now: Date())
            if let live = engine.world.live {
                switch live.state {
                case .encoding: return "Prime skipped. Focusing."
                case .recall: return "Break skipped. Recall: what did you just do?"
                case .priming, .paused, .onBreak: return "Advanced."
                }
            }
            if let note = engine.world.profile.lastNote {
                return "Session saved. \(note)"
            }
            return "Session saved."
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
            return world.live == nil ? 0 : 0
        }

        print(humanStatus(world, now: Date()))
        return 0
    }

    static func humanStatus(_ world: World, now: Date) -> String {
        guard let live = world.live else {
            var lines = ["Flowmo  idle"]
            if world.profile.sessionCount > 0 {
                lines.append("sessions \(world.profile.sessionCount)   ratio \(trim(world.profile.breakRatio))")
            }
            if let note = world.profile.lastNote {
                lines.append(note)
            }
            return lines.joined(separator: "\n")
        }

        let view = Engine.viewStatus(live, now: now)
        switch view.state {
        case .priming:
            return """
            Flowmo  prime  \(view.label)
            \(Format.clock(view.elapsed)) / \(Format.clock(live.primeDuration))
            skip when you're ready
            """
        case .encoding:
            return """
            Flowmo  focusing  \(view.label)
            \(Format.clock(view.elapsed))
            \(captureLine(view.captures))
            """
        case .paused:
            return """
            Flowmo  paused  \(view.label)
            \(Format.clock(view.elapsed))
            resume to continue
            """
        case .onBreak:
            let remaining = view.remaining ?? 0
            return """
            Flowmo  break  \(view.label)
            \(Format.clock(remaining)) remaining
            earned from \(Format.minutes(view.focusSeconds)) focus
            """
        case .recall:
            return """
            Flowmo  recall  \(view.label)
            What did you just do?
            \(Format.clock(view.elapsed)) / \(Format.clock(live.recallDuration))
            """
        }
    }

    static func captureLine(_ captures: [CaptureItem]) -> String {
        if captures.isEmpty { return "capture <thought> to park a line" }
        if captures.count == 1 { return "1 thought parked" }
        return "\(captures.count) thoughts parked"
    }

    static func trim(_ value: Double) -> String {
        String(format: "%g", value)
    }

    static let help = """
    flowmo — start a focus session

    flowmo start [label]     setup + prime (writing, code, study, …)
    flowmo stop              end focus, start earned break
    flowmo skip              skip prime, break, or recall
    flowmo pause | resume    pause only while focusing
    flowmo capture <text>    park a thought without leaving
    flowmo cancel            abandon the session
    flowmo status            where you are
    flowmo status --json     same, for agents
    """
}

private struct StatusPayload: Encodable {
    var running: Bool
    var state: String?
    var label: String?
    var elapsed: TimeInterval?
    var remaining: TimeInterval?
    var focusSeconds: TimeInterval?
    var breakSeconds: TimeInterval?
    var ratio: Double
    var captures: [String]
    var sessionCount: Int
    var lastNote: String?

    init(world: World, now: Date) {
        sessionCount = world.profile.sessionCount
        lastNote = world.profile.lastNote
        ratio = world.profile.breakRatio
        if let live = world.live {
            let view = Engine.viewStatus(live, now: now)
            running = true
            state = view.state.rawValue
            label = view.label
            elapsed = view.elapsed
            remaining = view.remaining
            focusSeconds = view.focusSeconds
            breakSeconds = view.breakSeconds
            ratio = view.ratio
            captures = view.captures.map(\.text)
        } else {
            running = false
            state = nil
            label = nil
            elapsed = nil
            remaining = nil
            focusSeconds = nil
            breakSeconds = nil
            captures = []
        }
    }
}

CLI.main()
