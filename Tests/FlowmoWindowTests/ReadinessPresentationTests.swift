import FlowmoCore
import FlowmoLook
import FlowmoSync
import XCTest

@testable import FlowmoWindow

@MainActor
final class ReadinessPresentationTests: XCTestCase {
    func testSyncConflictExpandsMiniAndRestoresItsPreference() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "flowmo-readiness-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(DisplayMode.mini.rawValue, forKey: "FlowmoDisplayMode")
        defaults.set(IntroductionState.currentVersion, forKey: IntroductionState.completionKey)
        let store = Store(root: root)
        try store.save(.empty)
        let syncStatus = WorldSyncStatus()
        let controller = FlowmoSessionController(
            store: store,
            attention: AttentionAdapter(canNotify: false),
            userDefaults: defaults,
            syncStatus: syncStatus
        )
        let delegate = AppDelegate(controller: controller)
        let window = delegate.makeWindow()
        delegate.window = window
        delegate.observeWindowContentSize()
        XCTAssertEqual(window.contentView?.frame.size, DisplayMode.mini.windowContentSize)

        let snapshot = WorldSyncSnapshot(world: .empty, generation: UUID())
        syncStatus.update(
            phase: .needsChoice,
            conflict: WorldSyncConflict(kind: .initialImport, local: snapshot, remote: snapshot, ancestor: nil)
        )

        XCTAssertEqual(controller.effectiveWindowContentSize, DisplayMode.classic.windowContentSize)
        XCTAssertEqual(window.contentView?.frame.size, DisplayMode.classic.windowContentSize)
        XCTAssertEqual(window.contentMinSize, DisplayMode.classic.windowContentSize)
        XCTAssertEqual(window.contentMaxSize, DisplayMode.classic.windowContentSize)
        XCTAssertEqual(defaults.string(forKey: "FlowmoDisplayMode"), DisplayMode.mini.rawValue)

        syncStatus.update(phase: .synced)
        XCTAssertEqual(window.contentView?.frame.size, DisplayMode.mini.windowContentSize)
        XCTAssertEqual(controller.displayMode, .mini)
        XCTAssertNil(try store.load().live)
    }
}
