import FlowmoCore
import XCTest

@testable import FlowmoPhone

final class PhoneFocusSceneTests: XCTestCase {
    func testDistantHorizonIsOnlyTheActiveUnpausedFocusPresentation() {
        XCTAssertTrue(
            PhoneFocusPresentation.usesDistantHorizon(
                phase: .focus,
                isPaused: false,
                storeNeedsRecovery: false,
                hasSyncConflict: false
            )
        )

        for phase in [SessionPhase.prime, .onBreak, .recall, .closeBeat] {
            XCTAssertFalse(
                PhoneFocusPresentation.usesDistantHorizon(
                    phase: phase,
                    isPaused: false,
                    storeNeedsRecovery: false,
                    hasSyncConflict: false
                )
            )
        }
        XCTAssertFalse(
            PhoneFocusPresentation.usesDistantHorizon(
                phase: nil,
                isPaused: false,
                storeNeedsRecovery: false,
                hasSyncConflict: false
            )
        )
    }

    func testDistantHorizonYieldsToRecoveryAndConflictSurfaces() {
        XCTAssertFalse(
            PhoneFocusPresentation.usesDistantHorizon(
                phase: .focus,
                isPaused: true,
                storeNeedsRecovery: false,
                hasSyncConflict: false
            )
        )
        XCTAssertFalse(
            PhoneFocusPresentation.usesDistantHorizon(
                phase: .focus,
                isPaused: false,
                storeNeedsRecovery: true,
                hasSyncConflict: false
            )
        )
        XCTAssertFalse(
            PhoneFocusPresentation.usesDistantHorizon(
                phase: .focus,
                isPaused: false,
                storeNeedsRecovery: false,
                hasSyncConflict: true
            )
        )
    }
}
