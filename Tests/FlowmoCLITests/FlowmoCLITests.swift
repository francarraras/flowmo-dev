import Foundation
import XCTest

@testable import FlowmoCLI
@testable import FlowmoCore

final class FlowmoCLITests: XCTestCase {
    func testJSONFlagIsRemovedFromTextOperandsRegardlessOfPlacement() {
        let leading = Invocation(args: ["start", "--json", "write", "the", "spec"])
        let trailing = Invocation(args: ["capture", "park", "this", "--json"])

        XCTAssertEqual(leading?.operands, ["write", "the", "spec"])
        XCTAssertTrue(leading?.json == true)
        XCTAssertEqual(trailing?.operands, ["park", "this"])
        XCTAssertTrue(trailing?.json == true)
    }

    func testStatusEnvelopeCarriesStableVersionAndGenerationMetadata() throws {
        var world = World.empty
        world.profile.lastNote = "Legacy ratio movement note."
        let payload = StatusEnvelope(
            status: StatusPayload(world: world, now: Date(timeIntervalSince1970: 1_700_000_000)),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )

        let json = try object(payload)
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(json["generatedAt"] as? String)
        let status = try XCTUnwrap(json["status"] as? [String: Any])
        XCTAssertNil(status["ratioReason"])
    }

    func testActionEnvelopeDoesNotEchoPrivateText() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let privateIntention = "synthetic private intention"
        let privateCapture = "synthetic private parked thought"
        var engine = Engine()
        try engine.apply(.start(intention: privateIntention), now: start)
        try engine.apply(.skip, now: start.addingTimeInterval(1))
        try engine.apply(.capture(privateCapture), now: start.addingTimeInterval(2))
        let payload = ActionEnvelope(
            command: "start",
            message: "Priming.",
            state: StatePayload(world: engine.world, now: start.addingTimeInterval(3)),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )

        let data = try JSONEncoder.flowmo.encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(json["command"] as? String, "start")
        XCTAssertEqual(
            Set(json.keys),
            Set(["schemaVersion", "generatedAt", "ok", "command", "message", "state"])
        )
        let state = try XCTUnwrap(json["state"] as? [String: Any])
        XCTAssertEqual(Set(state.keys), Set(["running", "phase", "paused"]))
        let rawJSON = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(rawJSON.contains(privateIntention))
        XCTAssertFalse(rawJSON.contains(privateCapture))
    }

    func testEngineAndUnsupportedControlErrorsUseStableEnvelopes() throws {
        let engine = FlowmoCLI.errorEnvelope(for: EngineError.nothingRunning)
        let paused = FlowmoCLI.errorEnvelope(for: EngineError.recoveryPaused)
        let control = FlowmoCLI.errorEnvelope(for: CLIError.unsupportedControl("not a flow control"))

        let engineJSON = try object(engine)
        let pausedJSON = try object(paused)
        let controlJSON = try object(control)
        XCTAssertEqual(errorCode(in: engineJSON), "nothing_running")
        XCTAssertEqual(errorCode(in: pausedJSON), "recovery_paused")
        XCTAssertEqual(errorCode(in: controlJSON), "unsupported_control")
        XCTAssertEqual(engineJSON["ok"] as? Bool, false)
        XCTAssertNotNil(engineJSON["generatedAt"] as? String)
    }

    func testLegacyHumanMessagesStayStable() {
        XCTAssertEqual(FlowmoCLI.help.contains("status --json"), true)
        XCTAssertEqual(
            FlowmoCLI.humanStatus(.empty, now: Date(timeIntervalSince1970: 1_700_000_000)),
            "Flowmo  idle\nlast —\ntoday 00:00\nratio 5"
        )
    }

    func testSkipMessageDescribesTheEngineReturnedByEachTransition() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var engine = Engine()
        try engine.apply(.start(intention: "write"), now: start)

        try engine.apply(.skip, now: start)
        XCTAssertEqual(FlowmoCLI.skipMessage(for: engine.world), "Focusing.")

        try engine.apply(.skip, now: start.addingTimeInterval(100))
        XCTAssertEqual(FlowmoCLI.skipMessage(for: engine.world), "Break started.")

        try engine.apply(.skip, now: start.addingTimeInterval(101))
        XCTAssertEqual(
            FlowmoCLI.skipMessage(for: engine.world),
            "Reflection: Where will you pick up next?"
        )

        try engine.apply(.skip, now: start.addingTimeInterval(102))
        XCTAssertEqual(FlowmoCLI.skipMessage(for: engine.world), "Close beat.")

        try engine.apply(.skip, now: start.addingTimeInterval(103))
        XCTAssertEqual(FlowmoCLI.skipMessage(for: engine.world), "Idle.")
    }

    func testEveryActionVerbPersistsThroughTheSelectedStore() throws {
        try withStore { store in
            XCTAssertEqual(try FlowmoCLI.run(["start", "synthetic intention"], store: store), 0)
            XCTAssertEqual(try store.load().live?.phase, .prime)

            XCTAssertEqual(try FlowmoCLI.run(["skip"], store: store), 0)
            XCTAssertEqual(try store.load().live?.phase, .focus)

            XCTAssertEqual(try FlowmoCLI.run(["capture", "synthetic thought"], store: store), 0)
            XCTAssertEqual(try FlowmoCLI.run(["log", "synthetic alias"], store: store), 0)
            XCTAssertEqual(try store.load().live?.captures.map(\.text), ["synthetic thought", "synthetic alias"])

            XCTAssertEqual(try FlowmoCLI.run(["stop"], store: store), 0)
            XCTAssertEqual(try store.load().live?.phase, .onBreak)

            XCTAssertEqual(try FlowmoCLI.run(["skip"], store: store), 0)
            XCTAssertEqual(try store.load().live?.phase, .recall)

            XCTAssertEqual(try FlowmoCLI.run(["recall", "synthetic next step"], store: store), 0)
            XCTAssertEqual(try store.load().live?.recallText, "synthetic next step")

            XCTAssertEqual(try FlowmoCLI.run(["skip"], store: store), 0)
            XCTAssertEqual(try store.load().live?.phase, .closeBeat)

            XCTAssertEqual(try FlowmoCLI.run(["skip"], store: store), 0)
            let completed = try store.load()
            XCTAssertNil(completed.live)
            XCTAssertEqual(completed.history.last?.recallText, "synthetic next step")

            XCTAssertEqual(try FlowmoCLI.run(["start", "synthetic recovery"], store: store), 0)
            let originalID = try XCTUnwrap(store.load().live?.id)
            _ = try store.update { engine in
                try engine.apply(.pauseForRecovery, now: Date())
            }

            XCTAssertEqual(try FlowmoCLI.run(["continue"], store: store), 0)
            let continued = try XCTUnwrap(store.load().live)
            XCTAssertEqual(continued.id, originalID)
            XCTAssertFalse(continued.isPaused)

            _ = try store.update { engine in
                try engine.apply(.pauseForRecovery, now: Date())
            }
            XCTAssertEqual(try FlowmoCLI.run(["restart"], store: store), 0)
            let restarted = try XCTUnwrap(store.load().live)
            XCTAssertNotEqual(restarted.id, originalID)
            XCTAssertEqual(restarted.phase, .prime)
            XCTAssertEqual(restarted.intention, "synthetic recovery")
            XCTAssertFalse(restarted.isPaused)

            XCTAssertEqual(try FlowmoCLI.run(["cancel"], store: store), 0)
            XCTAssertNil(try store.load().live)
        }
    }

    func testHumanErrorRenderingNeutralizesTerminalControlsFromHostileRawJSONKey() throws {
        let hostileKey = "café\u{1B}[2J\u{7F}\u{85}\u{2028}\u{2029}"
        var object: Any = "leaf"
        for _ in 0...WorldPersistenceLimits.maximumJSONDepth {
            object = [hostileKey: object]
        }
        let data = try JSONSerialization.data(withJSONObject: object)

        let validationError: Error
        do {
            try RawWorldValidation.validate(data)
            XCTFail("Hostile nested JSON should fail raw validation")
            return
        } catch {
            validationError = error
        }
        let rendered = FlowmoCLI.stderrLine(validationError.localizedDescription)

        XCTAssertTrue(rendered.contains("café"))
        XCTAssertFalse(
            rendered.unicodeScalars.contains { scalar in
                let code = scalar.value
                return code <= 0x1F
                    || code == 0x7F
                    || (0x80...0x9F).contains(code)
                    || code == 0x2028
                    || code == 0x2029
            })
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder.flowmo.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func errorCode(in object: [String: Any]) -> String? {
        (object["error"] as? [String: Any])?["code"] as? String
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }
}
