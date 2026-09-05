import AppKit
import FlowmoCore
import FlowmoLook
import FlowmoSync
import XCTest

@testable import FlowmoWindow

@MainActor
final class IntroductionTests: XCTestCase {
    func testSkipAndCompletionRemainDismissedInANewStateAndAllowExplicitReplay() throws {
        for finishOnLastPage in [false, true] {
            try withFixture { fixture in
                let introduction = IntroductionState(userDefaults: fixture.defaults)
                introduction.presentIfNeeded(canPresent: true)
                if finishOnLastPage {
                    introduction.next()
                    introduction.next()
                }
                introduction.finish()

                let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: fixture.suite))
                let reopened = IntroductionState(userDefaults: reopenedDefaults)
                XCTAssertTrue(reopened.hasCompleted)
                reopened.presentIfNeeded(canPresent: true)
                XCTAssertFalse(reopened.isPresented)
                reopened.replay(canPresent: false)
                XCTAssertFalse(reopened.isPresented)
                reopened.replay(canPresent: true)
                XCTAssertTrue(reopened.isPresented)
                XCTAssertEqual(reopened.page, 0)
                XCTAssertTrue(reopened.hasCompleted)
                XCTAssertEqual(try fixture.store.load(), .empty)
            }
        }
    }

    func testIntroductionTemporarilyExpandsMiniAndPreservesWorldDraftAndPreference() throws {
        _ = NSApplication.shared
        try withFixture { fixture in
            fixture.defaults.set(DisplayMode.mini.rawValue, forKey: "FlowmoDisplayMode")
            let controller = fixture.controller()
            controller.intentionDraft = "synthetic draft to retain"
            let before = try Data(contentsOf: fixture.store.worldURL)
            let delegate = AppDelegate(controller: controller)
            let window = delegate.makeWindow()
            delegate.window = window
            delegate.observeWindowContentSize()
            XCTAssertEqual(window.contentView?.frame.size, DisplayMode.mini.windowContentSize)

            controller.presentIntroductionIfNeeded()
            XCTAssertTrue(controller.introduction.isPresented)
            XCTAssertEqual(window.contentView?.frame.size, DisplayMode.classic.windowContentSize)
            XCTAssertEqual(window.contentMinSize, DisplayMode.classic.windowContentSize)
            XCTAssertEqual(window.contentMaxSize, DisplayMode.classic.windowContentSize)
            controller.introduction.next()
            controller.introduction.next()
            controller.introduction.finish()

            XCTAssertEqual(window.contentView?.frame.size, DisplayMode.mini.windowContentSize)
            XCTAssertEqual(window.contentMinSize, DisplayMode.mini.windowContentSize)
            XCTAssertEqual(window.contentMaxSize, DisplayMode.mini.windowContentSize)
            XCTAssertEqual(controller.displayMode, .mini)
            XCTAssertEqual(fixture.defaults.string(forKey: "FlowmoDisplayMode"), DisplayMode.mini.rawValue)
            XCTAssertEqual(controller.intentionDraft, "synthetic draft to retain")
            XCTAssertEqual(try Data(contentsOf: fixture.store.worldURL), before)

            controller.showIntroduction()
            XCTAssertTrue(controller.introduction.isPresented)
            XCTAssertEqual(window.contentView?.frame.size, DisplayMode.classic.windowContentSize)
            controller.introduction.finish()
            XCTAssertEqual(window.contentView?.frame.size, DisplayMode.mini.windowContentSize)
            XCTAssertEqual(controller.intentionDraft, "synthetic draft to retain")
            XCTAssertEqual(try Data(contentsOf: fixture.store.worldURL), before)
        }
    }

    func testExistingLiveAndRecoveryPausedSessionsDeferIntroductionWithoutResuming() throws {
        for paused in [false, true] {
            try withFixture { fixture in
                var engine = Engine()
                let now = Date()
                try engine.apply(.start(intention: "synthetic existing session"), now: now)
                try engine.apply(.skip, now: now)
                if paused { try engine.apply(.pauseForRecovery, now: now.addingTimeInterval(1)) }
                try fixture.store.save(engine.world)
                let savedWorld = try fixture.store.load()
                let before = try Data(contentsOf: fixture.store.worldURL)
                let controller = fixture.controller()
                controller.intentionDraft = "synthetic untouched draft"

                XCTAssertFalse(controller.canShowIntroduction)
                controller.presentIntroductionIfNeeded()
                controller.showIntroduction()
                XCTAssertFalse(controller.introduction.isPresented)
                XCTAssertFalse(controller.introduction.hasCompleted)
                XCTAssertEqual(controller.world, savedWorld)
                XCTAssertEqual(controller.intentionDraft, "synthetic untouched draft")
                XCTAssertEqual(try Data(contentsOf: fixture.store.worldURL), before)
            }
        }
    }

    func testIncomingSessionInterruptsTutorialWithoutMarkingItCompleteOrChangingTheSession() throws {
        try withFixture { fixture in
            let controller = fixture.controller()
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "synthetic tutorial draft"
            controller.presentIntroductionIfNeeded()
            controller.introduction.next()
            XCTAssertTrue(controller.introduction.isPresented)

            _ = try WorldAuthority(store: fixture.store).apply(
                .start(intention: "synthetic external session"), at: Date())
            controller.retryStore()
            let committedWorld = try fixture.store.load()
            let draft = controller.intentionDraft
            XCTAssertFalse(controller.canShowIntroduction)
            // The root invokes this hook when eligibility changes.
            controller.presentIntroductionIfNeeded()
            controller.introduction.finish()  // A late click from a removed page must not complete it.
            XCTAssertFalse(controller.introduction.isPresented)
            XCTAssertFalse(controller.introduction.hasCompleted)
            XCTAssertEqual(try fixture.store.load(), committedWorld)
            XCTAssertEqual(controller.intentionDraft, draft)

            _ = try WorldAuthority(store: fixture.store).apply(.cancel, at: Date())
            controller.retryStore()
            controller.presentIntroductionIfNeeded()
            XCTAssertTrue(controller.introduction.isPresented)
            XCTAssertEqual(controller.introduction.page, 0)
            XCTAssertNil(try fixture.store.load().live)
        }
    }

    func testConflictInterruptsTutorialAndDefersReplayWithoutTouchingWorldOrDraft() throws {
        try withFixture { fixture in
            let syncStatus = WorldSyncStatus()
            let controller = fixture.controller(syncStatus: syncStatus)
            controller.intentionDraft = "synthetic conflict draft"
            let before = try Data(contentsOf: fixture.store.worldURL)
            controller.presentIntroductionIfNeeded()
            controller.introduction.next()
            let snapshot = WorldSyncSnapshot(world: .empty, generation: UUID())
            let conflict = WorldSyncConflict(kind: .initialImport, local: snapshot, remote: snapshot, ancestor: nil)
            syncStatus.update(phase: .needsChoice, conflict: conflict)

            XCTAssertFalse(controller.canShowIntroduction)
            controller.presentIntroductionIfNeeded()
            controller.showIntroduction()
            controller.introduction.finish()
            XCTAssertFalse(controller.introduction.isPresented)
            XCTAssertFalse(controller.introduction.hasCompleted)
            XCTAssertEqual(controller.intentionDraft, "synthetic conflict draft")
            XCTAssertEqual(try Data(contentsOf: fixture.store.worldURL), before)

            syncStatus.update(phase: .synced)
            controller.presentIntroductionIfNeeded()
            XCTAssertTrue(controller.introduction.isPresented)
            XCTAssertEqual(controller.introduction.page, 0)
            controller.introduction.finish()
            controller.showIntroduction()
            syncStatus.update(phase: .needsChoice, conflict: conflict)
            controller.presentIntroductionIfNeeded()
            syncStatus.update(phase: .synced)
            controller.presentIntroductionIfNeeded()
            XCTAssertFalse(controller.introduction.isPresented)
            XCTAssertTrue(controller.introduction.hasCompleted)
            XCTAssertEqual(try Data(contentsOf: fixture.store.worldURL), before)
        }
    }

    func testUnreadableStoreDefersIntroductionAndPreservesInvalidBytes() throws {
        try withFixture { fixture in
            let invalid = Data("synthetic invalid store".utf8)
            try invalid.write(to: fixture.store.worldURL)
            let controller = fixture.controller()
            XCTAssertTrue(controller.storeNeedsRecovery)
            XCTAssertFalse(controller.canShowIntroduction)
            controller.presentIntroductionIfNeeded()
            controller.showIntroduction()
            XCTAssertFalse(controller.introduction.isPresented)
            XCTAssertFalse(controller.introduction.hasCompleted)
            XCTAssertEqual(try Data(contentsOf: fixture.store.worldURL), invalid)
        }
    }

    func testLifecycleRecoveryInterruptsIntroductionWithoutCompletingOrChangingWorld() throws {
        try withFixture { fixture in
            let controller = fixture.controller()
            controller.intentionDraft = "synthetic recovery draft"
            controller.presentIntroductionIfNeeded()
            let before = try Data(contentsOf: fixture.store.worldURL)
            let marker = fixture.store.root.appendingPathComponent("mac-process-recovery.json")
            try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
            controller.beginMacProcessLifetime()
            XCTAssertTrue(controller.lifecycleNeedsRecovery)
            XCTAssertFalse(controller.canShowIntroduction)
            controller.presentIntroductionIfNeeded()
            controller.introduction.finish()
            XCTAssertFalse(controller.introduction.isPresented)
            XCTAssertFalse(controller.introduction.hasCompleted)
            XCTAssertEqual(controller.intentionDraft, "synthetic recovery draft")
            XCTAssertEqual(try Data(contentsOf: fixture.store.worldURL), before)
        }
    }

    @MainActor
    private struct Fixture {
        let store: Store
        let defaults: UserDefaults
        let suite: String

        func controller(syncStatus: WorldSyncStatus = WorldSyncStatus()) -> FlowmoSessionController {
            FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                userDefaults: defaults,
                syncStatus: syncStatus
            )
        }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "flowmo-introduction-proof-\(UUID().uuidString)")
        let suite = "flowmo-introduction-proof-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = Store(root: root)
        try store.save(.empty)
        try body(Fixture(store: store, defaults: defaults, suite: suite))
    }
}
