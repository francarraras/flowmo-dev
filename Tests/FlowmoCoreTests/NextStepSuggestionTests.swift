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

    func testExactSessionSuggestionUsesOnlyItsTrimmedReflection() {
        let explicit = session(
            id: "00000000-0000-0000-0000-000000000001",
            endedAt: 100,
            recall: " \n carry this forward \t "
        )
        var blank = session(
            id: "00000000-0000-0000-0000-000000000002",
            endedAt: 200,
            recall: " \n "
        )
        blank.intention = "must not be used as a fallback"

        XCTAssertEqual(NextStepSuggestion.forSession(explicit), "carry this forward")
        XCTAssertNil(NextStepSuggestion.forSession(blank))
    }

    func testEqualTimestampsUseHistoryOrderDeterministically() {
        let sessions = [
            session(id: "ffffffff-ffff-ffff-ffff-ffffffffffff", endedAt: 100, recall: "later UUID"),
            session(id: "00000000-0000-0000-0000-000000000001", endedAt: 100, recall: "earlier UUID"),
        ]

        XCTAssertEqual(NextStepSuggestion.latest(in: sessions), "earlier UUID")
    }

    func testSelectedSessionResumptionPrefersItsNextStep() {
        let selected = session(
            id: "00000000-0000-0000-0000-000000000001",
            endedAt: 100,
            recall: "  finish the introduction  "
        )

        XCTAssertEqual(SessionResumptionSuggestion.forSession(selected), "finish the introduction")
    }

    func testSelectedSessionResumptionFallsBackToTrimmedIntention() {
        var selected = session(
            id: "00000000-0000-0000-0000-000000000001",
            endedAt: 100,
            recall: " \n "
        )
        selected.intention = " \t Return to draft \n "

        XCTAssertEqual(SessionResumptionSuggestion.forSession(selected), "Return to draft")
    }

    func testSelectedSessionResumptionReturnsNilWhenBothFieldsAreBlank() {
        var selected = session(
            id: "00000000-0000-0000-0000-000000000001",
            endedAt: 100,
            recall: " \n "
        )
        selected.intention = " \t "

        XCTAssertNil(SessionResumptionSuggestion.forSession(selected))
    }

    func testSelectedOlderSessionDoesNotUseNewerSessionCue() {
        let selectedOlder = session(
            id: "00000000-0000-0000-0000-000000000001",
            endedAt: 100,
            recall: "return to essay"
        )
        let newer = session(
            id: "00000000-0000-0000-0000-000000000002",
            endedAt: 200,
            recall: "newer task"
        )

        XCTAssertEqual(NextStepSuggestion.latest(in: [selectedOlder, newer]), "newer task")
        XCTAssertEqual(SessionResumptionSuggestion.forSession(selectedOlder), "return to essay")
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
