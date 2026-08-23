import Darwin
import FlowmoCore
import Foundation

enum LiveView {
    static func run() throws -> Int32 {
        signal(SIGINT, SIG_IGN)
        hideCursor()
        defer { showCursor() }

        let fd = FileHandle.standardInput.fileDescriptor

        while true {
            let world = try Store.default.update { engine in
                engine.sync(now: Date())
            }.world
            let frame = Format.liveView(Engine.sessionStatus(world, now: Date()))
            redraw(frame)

            if waitForQuit(fd: fd, timeoutMs: 250) {
                showCursor()
                fputs("\n", stdout)
                return 0
            }
        }
    }

    private static func redraw(_ frame: String) {
        let body = frame + "\n\nq  leave this view  ·  same session as the window"
        fputs("\u{1B}[H\u{1B}[2J" + body, stdout)
        fflush(stdout)
    }

    /// Do not use FileHandle.availableData: empty non-blocking stdin throws
    /// NSFileHandleOperationException (EAGAIN).
    private static func waitForQuit(fd: Int32, timeoutMs: Int32) -> Bool {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, timeoutMs)
        guard ready > 0, pfd.revents & Int16(POLLIN) != 0 else { return false }

        var buf = [UInt8](repeating: 0, count: 64)
        let n = buf.withUnsafeMutableBytes { raw in
            Darwin.read(fd, raw.baseAddress, raw.count)
        }
        if n == 0 { return true }
        guard n > 0 else { return false }
        let chunk = buf.prefix(Int(n))
        if chunk.contains(0x03) { return true }
        if chunk.contains(0x1B) { return true }
        return chunk.contains { byte in
            byte == UInt8(ascii: "q") || byte == UInt8(ascii: "Q")
        }
    }

    private static func hideCursor() {
        fputs("\u{1B}[?25l", stdout)
        fflush(stdout)
    }

    private static func showCursor() {
        fputs("\u{1B}[?25h", stdout)
        fflush(stdout)
    }
}
