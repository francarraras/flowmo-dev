import XCTest

@testable import FlowmoCore

final class FlowmoCoreTests: XCTestCase {
    func testPackageProvidesXCTestCoverageForTheCoreModule() {
        XCTAssertEqual(BreakMath.earnedBreak(focus: 600, ratio: 5), 120)
    }

    func testProfileRecorderNeverInfersRecoveryFromFocusDuration() {
        var longProfile = Profile.default
        var shortProfile = Profile.default

        for _ in 0..<3 {
            longProfile = ProfileRecorder.apply(longProfile, focusSeconds: 50 * 60)
            shortProfile = ProfileRecorder.apply(shortProfile, focusSeconds: 10 * 60)
        }

        XCTAssertEqual(longProfile.breakRatio, 5)
        XCTAssertEqual(shortProfile.breakRatio, 5)
        XCTAssertTrue(longProfile.recentFocusSeconds.isEmpty)
        XCTAssertTrue(shortProfile.recentFocusSeconds.isEmpty)
        XCTAssertNil(longProfile.lastNote)
        XCTAssertNil(shortProfile.lastNote)
    }
}
