import Darwin
import FlowmoCore
import Foundation

enum LiveView {
    static func run(store: Store = .default) throws -> Int32 {
        let input = FileHandle.standardInput.fileDescriptor
        guard isatty(input) == 1, isatty(FileHandle.standardOutput.fileDescriptor) == 1 else {
            throw CLIError.terminalUnavailable
        }
        let signals = LiveSignals()
        defer { signals.restore() }
        let terminal = try LiveTerminal(input: input)
        defer { terminal.restore() }

        while true {
            if let received = signals.received { return 128 + received }
            let world = try store.update { engine in
                engine.sync(now: Date())
            }.world
            let frame = Format.liveView(Engine.sessionStatus(world, now: Date()))
            redraw(frame)
            if try waitForQuit(fd: input, timeoutMs: 250) { return 0 }
        }
    }

    private static func redraw(_ frame: String) {
        let body = frame + "\n\nq / Esc / Ctrl-C  leave  ·  same session as the window"
        fputs("\u{1B}[H\u{1B}[2J" + body, stdout)
        fflush(stdout)
    }

    /// Poll the terminal directly: FileHandle.availableData may throw an
    /// Objective-C exception for nonblocking EAGAIN, which Swift cannot catch.
    private static func waitForQuit(fd: Int32, timeoutMs: Int32) throws -> Bool {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, timeoutMs)
        if ready < 0 {
            if errno == EINTR { return false }
            throw CLIError.terminalUnavailable
        }
        guard ready > 0 else { return false }
        if pfd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { return true }
        guard pfd.revents & Int16(POLLIN) != 0 else { return false }

        var buf = [UInt8](repeating: 0, count: 64)
        let n = buf.withUnsafeMutableBytes { raw in
            Darwin.read(fd, raw.baseAddress, raw.count)
        }
        if n == 0 { return true }
        if n < 0 {
            if errno == EINTR || errno == EAGAIN { return false }
            throw CLIError.terminalUnavailable
        }
        return buf.prefix(Int(n)).contains { byte in
            byte == 0x03 || byte == 0x04 || byte == 0x1B
                || byte == UInt8(ascii: "q") || byte == UInt8(ascii: "Q")
        }
    }
}

/// Change only input behavior; retain the terminal's normal newline handling.
/// The alternate screen preserves the shell's contents and scrollback.
private struct LiveTerminal {
    let input: Int32
    let original: termios

    init(input: Int32) throws {
        self.input = input
        var settings = termios()
        guard tcgetattr(input, &settings) == 0 else { throw CLIError.terminalUnavailable }
        original = settings
        settings.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG | IEXTEN)
        settings.c_iflag &= ~tcflag_t(IXON | IXOFF)
        withUnsafeMutableBytes(of: &settings.c_cc) { controls in
            controls[Int(VMIN)] = 1
            controls[Int(VTIME)] = 0
        }
        guard tcsetattr(input, TCSANOW, &settings) == 0 else { throw CLIError.terminalUnavailable }
        fputs("\u{1B}[?1049h\u{1B}[?25l", stdout)
        fflush(stdout)
    }

    func restore() {
        var settings = original
        _ = tcsetattr(input, TCSANOW, &settings)
        fputs("\u{1B}[?25h\u{1B}[?1049l", stdout)
        fflush(stdout)
    }
}

/// Dispatch signal callbacks run off the main thread while the view polls.
/// Protect their one shared value and restore the previous process handlers.
private final class LiveSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var signalNumber: Int32?
    private var sources: [DispatchSourceSignal] = []
    private var previous: [(Int32, sig_t?)] = []

    var received: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return signalNumber
    }

    init() {
        for number in [SIGINT, SIGTERM, SIGHUP] {
            previous.append((number, signal(number, SIG_IGN)))
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.lock.lock()
                if self.signalNumber == nil { self.signalNumber = number }
                self.lock.unlock()
            }
            sources.append(source)
            source.resume()
        }
    }

    func restore() {
        for source in sources { source.cancel() }
        for (number, handler) in previous { signal(number, handler) }
    }
}
