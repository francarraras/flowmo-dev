import FlowmoCore
import XCTest

@testable import FlowmoSync

final class WorldSyncRecordCodecTests: XCTestCase {
    func testRoundTripUsesOneHeadAndOneRecordPerCompletedSession() throws {
        let first = completed(id: uuid(1))
        let second = completed(id: uuid(2))
        var world = World.empty
        world.history = [second, first]
        let snapshot = WorldSyncSnapshot(world: world, generation: uuid(9))

        let records = try WorldSyncRecordCodec.records(for: snapshot)

        XCTAssertEqual(records.filter { $0.kind == .head }.map(\.name), ["world-head"])
        XCTAssertEqual(records.filter { $0.kind == .completedSession }.count, 2)
        let head = try XCTUnwrap(records.first { $0.kind == .head })
        let sessions = Dictionary(
            uniqueKeysWithValues: records.filter { $0.kind == .completedSession }.map { ($0.name, $0.data) })
        XCTAssertEqual(try WorldSyncRecordCodec.assemble(headData: head.data, sessionDataByName: sessions), snapshot)
    }

    func testAssemblyRejectsMissingAndMismatchedSessionRecords() throws {
        let session = completed(id: uuid(1))
        var world = World.empty
        world.history = [session]
        let snapshot = WorldSyncSnapshot(world: world, generation: uuid(9))
        let head = try XCTUnwrap(try WorldSyncRecordCodec.records(for: snapshot).first { $0.kind == .head })

        XCTAssertThrowsError(try WorldSyncRecordCodec.assemble(headData: head.data, sessionDataByName: [:])) {
            XCTAssertEqual($0 as? WorldSyncRecordError, .missingSession(session.id))
        }

        let wrong = completed(id: uuid(2))
        let wrongData = try JSONEncoder.flowmo.encode(wrong)
        XCTAssertThrowsError(
            try WorldSyncRecordCodec.decodeSession(
                wrongData,
                recordName: WorldSyncRecordCodec.sessionRecordName(session.id)
            )
        ) {
            XCTAssertEqual($0 as? WorldSyncRecordError, .sessionIdentityMismatch)
        }
    }

    private func completed(id: UUID) -> CompletedSession {
        CompletedSession(
            id: id,
            intention: "private",
            focusSeconds: 600,
            breakSeconds: 120,
            captureCount: 0,
            recallText: nil,
            endedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
