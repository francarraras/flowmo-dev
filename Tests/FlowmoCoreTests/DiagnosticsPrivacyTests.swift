import Foundation
import XCTest

@testable import FlowmoCore

final class DiagnosticsPrivacyTests: XCTestCase {
    func testExportCancellationIsRecognizedWithoutTreatingOtherErrorsAsCancellation() {
        XCTAssertTrue(FlowmoExportResult.isUserCancellation(CocoaError(.userCancelled)))
        XCTAssertFalse(FlowmoExportResult.isUserCancellation(CocoaError(.fileWriteUnknown)))
    }

    func testDiagnosticReportOmitsPlantedPrivateValues() throws {
        let plantedIntention = "PLANTED-INTENTION-SECRET"
        let plantedCapture = "PLANTED-CAPTURE-SECRET"
        let plantedRecall = "PLANTED-RECALL-SECRET"
        let plantedNote = "PLANTED-NOTE-SECRET"
        let plantedBundleID = "secret.bundle.identifier"
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let live = SessionSnapshot(
            id: UUID(),
            intention: plantedIntention,
            phase: .focus,
            breakRatio: 5,
            startedAt: timestamp,
            phaseStartedAt: timestamp,
            focusStartedAt: timestamp,
            focusEndedAt: nil,
            breakStartedAt: nil,
            breakDuration: nil,
            captures: [CaptureItem(text: plantedCapture, createdAt: timestamp)],
            primeDuration: 120,
            recallDuration: 180,
            recallText: plantedRecall
        )
        let history = CompletedSession(
            id: UUID(),
            intention: plantedIntention,
            focusSeconds: 600,
            breakSeconds: 120,
            captureCount: 1,
            recallText: plantedRecall,
            endedAt: timestamp,
            captures: [CaptureItem(text: plantedCapture, createdAt: timestamp)]
        )
        let world = World(
            live: live,
            profile: Profile(
                breakRatio: 5,
                sessionCount: 1,
                totalFocusSeconds: 600,
                recentFocusSeconds: [600],
                lastNote: plantedNote,
                lastIntention: plantedIntention
            ),
            config: Config(
                primeSeconds: 120,
                recallSeconds: 180,
                defaultBreakRatio: 5,
                focusGuard: FocusGuardConfiguration(enabled: true, bundleIdentifiers: [plantedBundleID])
            ),
            history: [history]
        )
        let report = FlowmoDiagnosticReport(
            generatedAt: timestamp,
            app: .init(name: "Flowmo", version: "1.2.3", build: "42", operatingSystem: "Test OS", platform: "test"),
            world: world,
            recentIssues: [.init(code: .persistenceFailed, operation: .update, occurredAt: timestamp)]
        )

        let encoded = try report.encoded()
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        for secret in [plantedIntention, plantedCapture, plantedRecall, plantedNote, plantedBundleID] {
            XCTAssertFalse(json.contains(secret), "Diagnostic JSON leaked a planted secret")
        }
        for privateKey in [
            "intention", "captures", "recallText", "lastIntention", "lastNote", "bundleIdentifiers", "worldURL",
            "storePath",
        ] {
            XCTAssertFalse(json.contains("\"\(privateKey)\""), "Diagnostic JSON included private key \(privateKey)")
        }
        XCTAssertTrue(json.contains(FlowmoIssueCode.persistenceFailed.rawValue))
        XCTAssertTrue(json.contains(FlowmoDiagnosticOperation.update.rawValue))
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
    }
}
