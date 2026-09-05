import Darwin
import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoWindow

@MainActor
final class MacRecoveryProcessTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private let childStoreKey = "FLOWMO_RECOVERY_PROCESS_PROOF_STORE"

    func testIndependentOwnerExcludesContendersAndRecoversAfterQuitOrCrash() throws {
        if let path = ProcessInfo.processInfo.environment[childStoreKey] {
            try runChildOwner(root: URL(fileURLWithPath: path, isDirectory: true))
            return
        }

        for crash in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "flowmo-recovery-process-proof-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = Store(root: root)
            let initial = try store.update { engine in
                try engine.apply(.start(intention: "independent owner proof"), now: self.origin)
                try engine.apply(.skip, now: self.origin)
            }
            let sessionID = try XCTUnwrap(initial.world.live?.id)
            let child = Process()
            let input = Pipe()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            child.arguments = [
                "xctest", "-XCTest",
                "FlowmoWindowTests.MacRecoveryProcessTests/testIndependentOwnerExcludesContendersAndRecoversAfterQuitOrCrash",
                Bundle(for: Self.self).bundleURL.path,
            ]
            child.environment = [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "TMPDIR": FileManager.default.temporaryDirectory.path,
                "FLOWMO_HOME": root.path,
                childStoreKey: root.path,
            ]
            child.standardInput = input
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            defer {
                if child.isRunning {
                    kill(child.processIdentifier, SIGKILL)
                    child.waitUntilExit()
                }
            }
            try waitUntil {
                !child.isRunning || FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path)
            }
            XCTAssertTrue(child.isRunning, "The independent owner must remain alive until explicitly stopped.")
            guard child.isRunning else { return }

            let contender = MacProcessRecoveryMarker(store: store)
            var preparation = MacProcessRecoveryMarker.ClaimPreparation.prepared
            _ = try store.update { engine in
                preparation = try contender.prepareClaim(&engine, now: self.origin.addingTimeInterval(20))
            }
            XCTAssertEqual(preparation, .contended)
            XCTAssertFalse(contender.ownsLifecycle)
            XCTAssertEqual(try store.load(), initial.world)

            if crash {
                XCTAssertEqual(kill(child.processIdentifier, SIGKILL), 0)
            } else {
                try input.fileHandleForWriting.write(contentsOf: Data([1]))
            }
            try waitUntil { !child.isRunning }
            child.waitUntilExit()
            XCTAssertEqual(child.terminationStatus, crash ? SIGKILL : 0)
            XCTAssertEqual(child.terminationReason, crash ? .uncaughtSignal : .exit)

            let recovered = try store.update { engine in
                preparation = try contender.prepareClaim(&engine, now: self.origin.addingTimeInterval(3_600))
            }
            XCTAssertEqual(preparation, .prepared)
            contender.commitPreparedClaim()
            XCTAssertTrue(contender.ownsLifecycle)
            XCTAssertEqual(recovered.world.live?.id, sessionID)
            XCTAssertEqual(recovered.world.live?.phase, .focus)
            XCTAssertEqual(recovered.world.live?.pausedAt, origin.addingTimeInterval(10))
            XCTAssertEqual(recovered.status(now: origin.addingTimeInterval(7_200)).elapsed, 10)
            XCTAssertTrue(recovered.status(now: origin.addingTimeInterval(7_200)).isPaused)
            XCTAssertEqual(try store.load(), recovered.world)
        }
    }

    private func runChildOwner(root: URL) throws {
        guard root.lastPathComponent.hasPrefix("flowmo-recovery-process-proof-") else {
            throw NSError(domain: "MacRecoveryProcessTests.invalidFixture", code: 1)
        }
        let store = Store(root: root)
        let owner = MacProcessRecoveryMarker(store: store)
        _ = try store.update { engine in
            XCTAssertEqual(try owner.prepareClaim(&engine, now: self.origin), .prepared)
        }
        owner.commitPreparedClaim()
        _ = try store.update { engine in
            try owner.recordObservation(engine.world.live?.id, at: self.origin.addingTimeInterval(10))
        }
        try Data().write(to: root.appendingPathComponent("ready"))
        guard try FileHandle.standardInput.read(upToCount: 1) == Data([1]) else {
            throw NSError(domain: "MacRecoveryProcessTests.missingQuitRequest", code: 1)
        }
        _ = try store.update(
            { engine in try engine.apply(.pauseForRecovery, now: self.origin.addingTimeInterval(10)) },
            afterPersist: { _ in try owner.finishNormally() }
        )
    }

    private func waitUntil(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { usleep(10_000) }
        guard condition() else { throw NSError(domain: "MacRecoveryProcessTests.timeout", code: 1) }
    }
}
