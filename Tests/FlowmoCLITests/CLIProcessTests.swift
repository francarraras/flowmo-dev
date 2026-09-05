import Darwin
import Foundation
import XCTest

@testable import FlowmoCore

final class CLIProcessTests: XCTestCase {
    func testProcessHelpInvalidArgumentsAndVersionDoNotMutateSession() throws {
        try withStore { store in
            let before = try store.load()
            let help = try run(["cancel", "--help"], store: store)
            XCTAssertEqual(help.code, 0)
            XCTAssertTrue(help.output.contains("discard the current session"))
            for args in [["cancel", "--typo", "--json"], ["unknown", "--json"]] {
                let result = try run(args, store: store)
                XCTAssertNotEqual(result.code, 0)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
                XCTAssertEqual(json["ok"] as? Bool, false)
                XCTAssertFalse(result.output.contains("synthetic"))
            }
            let version = try run(["--version", "--json"], store: store)
            XCTAssertEqual(version.code, 0)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(version.output.utf8)) as? [String: Any])
            XCTAssertEqual(json["schemaVersion"] as? Int, 1)
            XCTAssertNotNil(json["version"] as? String)
            XCTAssertNotNil(json["build"] as? String)
            XCTAssertEqual(try store.load(), before)
        }
    }

    func testLiveRejectsRedirectedInputAndOutputWithoutTerminalEscapes() throws {
        try withStore { store in
            let before = try store.load()
            let result = try run(["live"], store: store)
            XCTAssertNotEqual(result.code, 0)
            XCTAssertTrue(result.output.contains("interactive terminal"))
            XCTAssertFalse(result.output.contains("\u{1B}"))
            XCTAssertEqual(try store.load(), before)
        }
    }

    func testLiveExitKeysAreImmediateAndRestoreTerminalWithoutChangingSession() throws {
        for byte: UInt8 in [UInt8(ascii: "q"), UInt8(ascii: "Q"), 0x1B, 0x03, 0x04] {
            try withStore { store in
                let before = try store.load()
                try withLiveTerminal(store: store) { process, master, output in
                    var key = byte
                    XCTAssertEqual(Darwin.write(master, &key, 1), 1)
                    try finish(process)
                    output.append(try drain(master))
                    XCTAssertEqual(process.terminationStatus, 0)
                }
                XCTAssertEqual(try store.load(), before)
            }
        }
    }

    func testLiveTerminationSignalsRestoreTerminalWithoutChangingSession() throws {
        for number in [SIGINT, SIGTERM, SIGHUP] {
            try withStore { store in
                let before = try store.load()
                try withLiveTerminal(store: store) { process, master, output in
                    XCTAssertEqual(kill(process.processIdentifier, number), 0)
                    try finish(process)
                    output.append(try drain(master))
                    XCTAssertEqual(process.terminationStatus, 128 + number)
                }
                XCTAssertEqual(try store.load(), before)
            }
        }
    }

    func testLiveStoreFailureRestoresTerminalBeforeReportingError() throws {
        try withStore { store in
            try withLiveTerminal(store: store) { process, master, output in
                try Data("invalid synthetic store".utf8).write(to: store.worldURL)
                try finish(process)
                output.append(try drain(master))
                XCTAssertNotEqual(process.terminationStatus, 0)
                let text = String(decoding: output, as: UTF8.self)
                let restored = try XCTUnwrap(text.range(of: "\u{1B}[?1049l"))
                let error = try XCTUnwrap(text.range(of: "Error:"))
                XCTAssertLessThan(restored.lowerBound, error.lowerBound)
            }
        }
    }

    private func withLiveTerminal(
        store: Store,
        body: (Process, Int32, inout Data) throws -> Void
    ) throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        XCTAssertEqual(openpty(&master, &slave, nil, nil, nil), 0)
        guard master >= 0, slave >= 0 else { throw ProcessProofError.noTerminal }
        defer {
            close(master)
            close(slave)
        }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        var original = termios()
        XCTAssertEqual(tcgetattr(slave, &original), 0)
        XCTAssertNotEqual(original.c_lflag & tcflag_t(ICANON), 0)
        let handle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        let process = try configuredProcess(["live"], store: store)
        process.standardInput = handle
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        var output = Data()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, process.isRunning {
            output.append(try drain(master))
            if String(decoding: output, as: UTF8.self).contains("leave  ·") { break }
            usleep(10_000)
        }
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("\u{1B}[?1049h"))
        var active = termios()
        XCTAssertEqual(tcgetattr(slave, &active), 0)
        XCTAssertEqual(active.c_lflag & tcflag_t(ICANON | ECHO | ISIG), 0)
        try body(process, master, &output)
        var restored = termios()
        XCTAssertEqual(tcgetattr(slave, &restored), 0)
        // Darwin sets PENDIN as kernel state when canonical input is restored.
        // It is not a user terminal setting changed by the view.
        XCTAssertEqual(restored.c_lflag & ~tcflag_t(PENDIN), original.c_lflag & ~tcflag_t(PENDIN))
        XCTAssertEqual(restored.c_iflag, original.c_iflag)
        XCTAssertEqual(restored.c_oflag, original.c_oflag)
        XCTAssertEqual(restored.c_cflag, original.c_cflag)
        let originalControls = withUnsafeBytes(of: original.c_cc) { Array($0) }
        let restoredControls = withUnsafeBytes(of: restored.c_cc) { Array($0) }
        XCTAssertEqual(restoredControls, originalControls)
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(text.contains("\u{1B}[?25h\u{1B}[?1049l"))
    }

    private func drain(_ fd: Int32) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                result.append(contentsOf: buffer.prefix(count))
            } else if count == 0 || errno == EAGAIN || errno == EIO {
                return result
            } else if errno != EINTR {
                throw ProcessProofError.readFailed
            }
        }
    }

    private func run(_ args: [String], store: Store) throws -> (code: Int32, output: String) {
        let process = try configuredProcess(args, store: store)
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        try input.fileHandleForWriting.close()
        try finish(process)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func finish(_ process: Process) throws {
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline { usleep(10_000) }
        guard !process.isRunning else {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            XCTFail("CLI did not exit promptly")
            throw ProcessProofError.timeout
        }
        process.waitUntilExit()
    }

    private func configuredProcess(_ args: [String], store: Store) throws -> Process {
        let process = Process()
        process.executableURL = try executable()
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(["FLOWMO_HOME": store.root.path]) { _, new in
            new
        }
        return process
    }

    private func executable() throws -> URL {
        var directory = Bundle(for: CLIProcessTests.self).bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("flowmo")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        throw ProcessProofError.missingExecutable
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "flowmo-process-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        var engine = Engine()
        let now = Date()
        try engine.apply(.start(intention: "synthetic process proof"), now: now)
        try engine.apply(.skip, now: now)
        try store.save(engine.world)
        try body(store)
    }
}

private enum ProcessProofError: Error {
    case noTerminal, readFailed, timeout, missingExecutable
}
