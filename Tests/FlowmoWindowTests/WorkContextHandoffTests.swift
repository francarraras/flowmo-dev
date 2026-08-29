import Foundation
import XCTest

@testable import FlowmoWindow

final class WorkContextHandoffTests: XCTestCase {
    func testBindingFreezesCandidateForOneSession() {
        let sessionID = UUID()
        var state = WorkContextHandoffState<String>()

        state.observe("Safari")
        state.bindCandidate(to: sessionID)
        state.observe("Xcode")

        XCTAssertEqual(state.target(for: sessionID), "Safari")
        XCTAssertNil(state.target(for: UUID()))
    }

    func testTransferPreservesTargetAndRejectsOldSession() {
        let oldID = UUID()
        let newID = UUID()
        var state = WorkContextHandoffState<String>()
        state.observe("TextEdit")
        state.bindCandidate(to: oldID)

        state.transfer(from: oldID, to: newID)

        XCTAssertNil(state.target(for: oldID))
        XCTAssertEqual(state.target(for: newID), "TextEdit")
    }

    func testRetainingAnotherOrNoSessionClearsTarget() {
        let sessionID = UUID()
        var state = WorkContextHandoffState<String>()
        state.observe("Safari")
        state.bindCandidate(to: sessionID)

        state.retainOnly(sessionID: UUID())
        XCTAssertNil(state.target(for: sessionID))

        state.bindCandidate(to: sessionID)
        state.retainOnly(sessionID: nil)
        XCTAssertNil(state.target(for: sessionID))
    }
}
