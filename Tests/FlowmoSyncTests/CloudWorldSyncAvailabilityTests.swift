import FlowmoCore
import XCTest

@testable import FlowmoSync

final class CloudWorldSyncAvailabilityTests: XCTestCase {
    func testContainerEntitlementRequiresExactConfiguredContainer() {
        XCTAssertTrue(
            CloudWorldSync.containerIdentifiers(
                from: ["iCloud.example", CloudWorldSync.containerIdentifier]
            ).contains(CloudWorldSync.containerIdentifier)
        )
        XCTAssertFalse(
            CloudWorldSync.containerIdentifiers(from: ["iCloud.example"])
                .contains(CloudWorldSync.containerIdentifier)
        )
        XCTAssertEqual(CloudWorldSync.containerIdentifiers(from: "iCloud.app.flowmo"), [])
        XCTAssertEqual(CloudWorldSync.containerIdentifiers(from: nil), [])
    }

    #if os(macOS)
        @MainActor
        func testDefaultAdapterStaysLocalOnlyInUnentitledTestProcess() throws {
            XCTAssertFalse(CloudWorldSync.currentProcessHasContainerEntitlement)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let status = WorldSyncStatus()

            let sync = CloudWorldSync.makeDefault(store: Store(root: root), status: status)

            XCTAssertNil(sync)
            XCTAssertEqual(status.phase, .unavailable)
            XCTAssertEqual(status.issueCode, "sync_entitlement_unavailable")
        }
    #endif
}
