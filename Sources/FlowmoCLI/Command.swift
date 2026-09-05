import FlowmoCore
import Foundation

public enum FlowmoCLI {
    /// Increment only for intentional, documented breaking changes to the JSON contract.
    public static let jsonSchemaVersion = 1

    public static let verbs: Set<String> = [
        "help", "-h", "--help", "version", "--version",
        "start", "stop", "skip", "continue", "restart", "cancel",
        "capture", "log", "recall", "status", "live", "check",
        "pause", "resume",
    ]

    public static func isInvocation(_ args: [String]) -> Bool {
        !args.isEmpty
    }

    public static func main(runChecks: (() -> Int32)? = nil) {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            let code = try run(args, runChecks: runChecks)
            exit(code)
        } catch {
            if jsonRequested(in: args) {
                writeJSON(errorEnvelope(for: error))
            } else if let cliError = error as? CLIError {
                writeError(cliError.message)
            } else if let engineError = error as? EngineError {
                writeError(engineError.description)
            } else {
                writeError("Error: \(error)")
            }
            exit(1)
        }
    }

    static func run(
        _ args: [String], store: Store = .default, runChecks: (() -> Int32)? = nil
    ) throws -> Int32 {
        guard let invocation = try Invocation(args: args) else {
            print(help)
            return 0
        }
        if invocation.wantsHelp {
            let content = commandHelp(invocation.helpCommand)
            if invocation.json {
                writeJSON(HelpEnvelope(help: content))
            } else {
                print(content)
            }
            return 0
        }
        let authority = WorldAuthority(store: store)

        switch invocation.command {
        case "version", "--version":
            let version = VersionEnvelope()
            if invocation.json {
                writeJSON(version)
            } else {
                print("flowmo \(version.version) (build \(version.build))")
            }
            return 0
        case "check":
            guard let runChecks else { throw CLIError.invalidArguments("Core proofs are unavailable in this host.") }
            return runChecks()
        case "start":
            let intention = invocation.operands.joined(separator: " ")
            let world = try authority.apply(.start(intention: intention), at: Date()).world
            return action(command: invocation.command, message: "Priming.", world: world, json: invocation.json)
        case "stop":
            let world = try authority.apply(.stopFocus, at: Date()).world
            return action(
                command: invocation.command, message: "Focus stopped. Break started.", world: world,
                json: invocation.json)
        case "skip":
            let world = try authority.apply(.skip, at: Date()).world
            return action(
                command: invocation.command,
                message: skipMessage(for: world),
                world: world,
                json: invocation.json)
        case "continue":
            let world = try authority.apply(.`continue`, at: Date()).world
            return action(command: invocation.command, message: "Continued.", world: world, json: invocation.json)
        case "restart":
            let world = try authority.apply(.restart, at: Date()).world
            return action(command: invocation.command, message: "Priming.", world: world, json: invocation.json)
        case "pause", "resume":
            let message =
                "pause/resume are not flow controls. Quit or sleep pauses for recovery; continue resumes that phase, restart primes the same intention again."
            if invocation.json {
                throw CLIError.unsupportedControl(message)
            }
            writeError(message)
            return 2
        case "cancel":
            let world = try authority.apply(.cancel, at: Date()).world
            return action(
                command: invocation.command, message: "Session cancelled.", world: world, json: invocation.json)
        case "capture", "log":
            let text = invocation.operands.joined(separator: " ")
            let world = try authority.apply(.capture(text), at: Date()).world
            return action(command: invocation.command, message: "Parked.", world: world, json: invocation.json)
        case "recall":
            let text = invocation.operands.joined(separator: " ")
            let world = try authority.apply(.setRecallText(text), at: Date()).world
            return action(
                command: invocation.command, message: "Next step saved.", world: world, json: invocation.json)
        case "status":
            return try status(json: invocation.json, store: store)
        case "live":
            return try LiveView.run(store: store)
        default:
            throw CLIError.unknownCommand
        }
    }

    static func action(command: String, message: String, world: World, json: Bool) -> Int32 {
        guard json else {
            print(message)
            return 0
        }
        writeJSON(
            ActionEnvelope(command: command, message: message, state: StatePayload(world: world, now: Date())))
        return 0
    }

    static func skipMessage(for world: World) -> String {
        guard let live = world.live else {
            return "Idle."
        }
        switch live.phase {
        case .prime: return "Session running."
        case .focus: return "Focusing."
        case .onBreak: return "Break started."
        case .recall: return "Reflection: \(FlowmoCopy.reflectionPrompt)"
        case .closeBeat: return "Close beat."
        }
    }

    static func status(json: Bool, store: Store = .default) throws -> Int32 {
        let world: World = try store.update { engine in
            engine.sync(now: Date())
        }.world

        if json {
            writeJSON(StatusEnvelope(status: StatusPayload(world: world, now: Date())))
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
        restart                  drop the frozen session and prime again
        capture <text>
        recall <text>
        cancel
        status
        status --json
        check                    core proofs
        --version                version and build

        <command> --help         explain a command without changing the session
        <command> --json         structured output (except live and check)
        <command> -- <text>      literal text, including words starting with '-'
        """

    static func jsonRequested(in args: [String]) -> Bool {
        args.dropFirst().prefix(while: { $0 != "--" }).contains("--json")
    }

    static func commandHelp(_ command: String?) -> String {
        guard let command else { return help }
        let description: String
        switch command {
        case "start": description = "start [intention] — begin Prime; omit text to use the saved intention."
        case "stop": description = "stop — end Focus and begin the proportional Break."
        case "skip":
            description = "skip — advance the current beat; during Focus, end Focus; at Close Beat, finish the session."
        case "continue": description = "continue — continue the frozen beat after quit or sleep recovery."
        case "restart": description = "restart — discard the frozen session and begin Prime with the same intention."
        case "cancel":
            description = "cancel — discard the current session and its parked thoughts; completed history stays."
        case "capture", "log": description = "\(command) <text> — park a thought during Focus without ending it."
        case "recall":
            description =
                "recall <text> — save the next step during Reflection; use an empty quoted string to clear it."
        case "status": description = "status — show the current session; --json includes private session text."
        case "live":
            description =
                "live — watch the session in an interactive terminal. q, Escape, or Ctrl-C leaves immediately."
        case "check": description = "check — run the core proofs without using your session store."
        case "version", "--version": description = "--version — show this executable's version and build."
        case "pause", "resume":
            description = "Pause and resume are not flow controls. Recovery uses continue or restart."
        default: return help
        }
        return "flowmo \(description)\n\nUse -- before literal text that starts with '-'."
    }

    static func errorEnvelope(for error: Error) -> ErrorEnvelope {
        switch error {
        case let engineError as EngineError:
            return ErrorEnvelope(code: engineError.code, message: engineError.description)
        case let cliError as CLIError:
            return ErrorEnvelope(code: cliError.code, message: cliError.message)
        default:
            // Do not expose store paths or other incidental process details to automation.
            return ErrorEnvelope(code: "command_failed", message: "The command could not be completed.")
        }
    }

    static func writeJSON<T: Encodable>(_ payload: T) {
        do {
            let data = try JSONEncoder.flowmo.encode(payload)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            writeError("Error: could not encode JSON output.")
        }
    }

    static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((stderrLine(message) + "\n").utf8))
    }

    /// Keep every human stderr path inert, including validation paths derived
    /// from hostile JSON object keys. JSON errors use their separate envelope.
    static func stderrLine(_ message: String) -> String {
        let scalars = message.unicodeScalars.map { scalar -> Unicode.Scalar in
            let code = scalar.value
            let isC0 = code <= 0x1F
            let isDelete = code == 0x7F
            let isC1 = (0x80...0x9F).contains(code)
            let isLineSeparator = code == 0x2028 || code == 0x2029
            return (isC0 || isDelete || isC1 || isLineSeparator) ? " " : scalar
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

struct Invocation {
    let command: String
    let operands: [String]
    let json: Bool
    let wantsHelp: Bool
    let helpCommand: String?

    init?(args: [String]) throws {
        guard let command = args.first else { return nil }
        guard FlowmoCLI.verbs.contains(command) else { throw CLIError.unknownCommand }
        self.command = command
        json = FlowmoCLI.jsonRequested(in: args)
        let options = args.dropFirst().prefix(while: { $0 != "--" })
        let isHelpCommand = ["help", "-h", "--help"].contains(command)
        wantsHelp = isHelpCommand || options.contains("--help") || options.contains("-h")
        if wantsHelp {
            if isHelpCommand {
                let targets = options.filter { $0 != "--json" && $0 != "--help" && $0 != "-h" }
                guard targets.count <= 1,
                    targets.first.map(FlowmoCLI.verbs.contains) ?? true
                else { throw CLIError.invalidArguments("Use flowmo help [command].") }
                helpCommand = targets.first
            } else {
                helpCommand = command
            }
            operands = []
            return
        }
        helpCommand = nil
        var text: [String] = []
        var literal = false
        for token in args.dropFirst() {
            if !literal, token == "--" {
                literal = true
            } else if !literal, token == "--json" {
                continue
            } else if !literal, token.hasPrefix("-"), token != "-" {
                throw CLIError.invalidArguments("Unsupported option. Use flowmo help, or -- before literal text.")
            } else {
                text.append(token)
            }
        }
        let acceptsText = ["start", "capture", "log", "recall"].contains(command)
        guard acceptsText || text.isEmpty else {
            throw CLIError.invalidArguments("This command does not accept text. Use flowmo help [command].")
        }
        if ["capture", "log", "recall"].contains(command), text.isEmpty {
            throw CLIError.invalidArguments("This command requires text. Use flowmo help [command].")
        }
        if json, ["live", "check"].contains(command) {
            throw CLIError.invalidArguments(
                "This command does not support --json. Use status --json to read the session.")
        }
        operands = text
    }
}

enum CLIError: Error {
    case unsupportedControl(String)
    case unknownCommand
    case invalidArguments(String)
    case terminalUnavailable

    var code: String {
        switch self {
        case .unsupportedControl: return "unsupported_control"
        case .unknownCommand: return "unknown_command"
        case .invalidArguments: return "invalid_arguments"
        case .terminalUnavailable: return "terminal_unavailable"
        }
    }

    var message: String {
        switch self {
        case .unsupportedControl(let message): return message
        case .unknownCommand: return "Unknown command. Run flowmo --help."
        case .invalidArguments(let message): return message
        case .terminalUnavailable:
            return "Live needs an interactive terminal for input and output. Use flowmo status for redirected output."
        }
    }
}

struct HelpEnvelope: Encodable {
    let schemaVersion = FlowmoCLI.jsonSchemaVersion
    let generatedAt = Date()
    let help: String
}

struct VersionEnvelope: Encodable {
    let schemaVersion = FlowmoCLI.jsonSchemaVersion
    let generatedAt = Date()
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        version = Self.metadata(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString"))
        build = Self.metadata(bundle.object(forInfoDictionaryKey: "CFBundleVersion"))
    }

    private static func metadata(_ value: Any?) -> String {
        guard let text = value as? String, !text.isEmpty, text.utf8.count <= 64,
            text.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || byte == 46 || byte == 45 || byte == 95
            })
        else { return "development" }
        return text
    }
}

extension EngineError {
    fileprivate var code: String {
        switch self {
        case .alreadyRunning: return "already_running"
        case .nothingRunning: return "nothing_running"
        case .notFocus: return "not_focusing"
        case .notPaused: return "not_paused"
        case .recoveryPaused: return "recovery_paused"
        case .cannotCapture: return "cannot_capture"
        case .emptyCapture: return "empty_capture"
        case .cannotSetRecallText: return "cannot_set_recall"
        case .notIdle: return "not_idle"
        }
    }
}

struct StatusEnvelope: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let status: StatusPayload

    init(status: StatusPayload, generatedAt: Date = Date()) {
        schemaVersion = FlowmoCLI.jsonSchemaVersion
        self.generatedAt = generatedAt
        self.status = status
    }
}

struct ActionEnvelope: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let ok = true
    let command: String
    let message: String
    let state: StatePayload

    init(command: String, message: String, state: StatePayload, generatedAt: Date = Date()) {
        schemaVersion = FlowmoCLI.jsonSchemaVersion
        self.generatedAt = generatedAt
        self.command = command
        self.message = message
        self.state = state
    }
}

struct ErrorEnvelope: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let ok = false
    let error: ErrorPayload

    init(code: String, message: String, generatedAt: Date = Date()) {
        schemaVersion = FlowmoCLI.jsonSchemaVersion
        self.generatedAt = generatedAt
        error = ErrorPayload(code: code, message: message)
    }
}

struct ErrorPayload: Encodable {
    let code: String
    let message: String
}

struct StatePayload: Encodable {
    let running: Bool
    let phase: String?
    let paused: Bool

    init(world: World, now: Date) {
        let status = Engine.sessionStatus(world, now: now)
        running = status.phase != nil
        phase = status.phase?.rawValue
        paused = status.isPaused
    }
}

struct StatusPayload: Encodable {
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
    var ratioReason: String?
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
        ratioReason = nil
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
