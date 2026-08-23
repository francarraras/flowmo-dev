import XCTest

@testable import FlowmoCore

final class FlowmoCoreTests: XCTestCase {
    func testPackageProvidesXCTestCoverageForTheCoreModule() {
        XCTAssertEqual(BreakMath.earnedBreak(focus: 600, ratio: 5), 120)
    }
}
