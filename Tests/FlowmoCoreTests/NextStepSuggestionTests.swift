import XCTest

@testable import FlowmoCore

final class NextStepSuggestionTests: XCTestCase {
    func testUsesReflectionFromNewestSession() {
        let sessions = [
            session(id: "00000000-0000-0000-0000-000000000001", endedAt: 100, recall: "old next step"),
            session(id: "00000000-0000-0000-0000-000000000002", endedAt: 200, recall: "new next step"),
        ]

        XCTAssertEqual(NextStepSuggestion.latest(in: sessions), "new next step")
    }

    func testTrimsWhitespaceAroundLatestReflection() {
        let sessions = [
            session(id: "00000000-0000-0000-0000-000000000001", endedAt: 100, recall: " \n next step \t ")
        ]

        XCTAssertEqual(NextStepSuggestion.latest(in: sessions), "next step")
    }

    func testDoesNotFallBackWhenLatestReflectionIsEmpty() {
        let sessions = [
            session(id: "00000000-0000-0000-0000-000000000001", endedAt: 100, recall: "older next step"),
            session(id: "00000000-0000-0000-0000-000000000002", endedAt: 200, recall: " \n "),
        ]

        XCTAssertNil(NextStepSuggestion.latest(in: sessions))
    }

    func testEqualTimestampsUseHistoryOrderDeterministically() {
        let sessions = [
            session(id: "ffffffff-ffff-ffff-ffff-ffffffffffff", endedAt: 100, recall: "later UUID"),
            session(id: "00000000-0000-0000-0000-000000000001", endedAt: 100, recall: "earlier UUID"),
        ]

        XCTAssertEqual(NextStepSuggestion.latest(in: sessions), "earlier UUID")
    }

    private func session(id: String, endedAt: TimeInterval, recall: String?) -> CompletedSession {
        CompletedSession(
            id: UUID(uuidString: id)!,
            intention: "writing",
            focusSeconds: 600,
            breakSeconds: 120,
            captureCount: 0,
            recallText: recall,
            endedAt: Date(timeIntervalSince1970: endedAt)
        )
    }
}
