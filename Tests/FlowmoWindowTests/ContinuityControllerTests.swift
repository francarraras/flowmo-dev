import AppKit
import FlowmoCore
import FlowmoSync
import Foundation
import XCTest

@testable import FlowmoWindow

@MainActor
final class ContinuityControllerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testClassicRestoreClampsAFormerMiniPositionIntoTheVisibleScreen() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_000, height: 700)

        let origin = AppDelegate.clampedWindowOrigin(
            pinnedTopLeft: NSPoint(x: 900, y: 150),
            windowSize: NSSize(width: 320, height: 460),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: 680, y: 0))
    }

    func testStartBindsWorkContextAndFocusNowHandsBackAfterTransition() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "write the report"

            controller.start()
            let sessionID = try XCTUnwrap(controller.world.live?.id)
            XCTAssertEqual(controller.world.live?.phase, .prime)
            XCTAssertEqual(handoff.boundSessionID, sessionID)
            XCTAssertTrue(handoff.activationRequests.isEmpty)

            controller.focusNow()
            XCTAssertEqual(controller.world.live?.phase, .focus)
            XCTAssertEqual(handoff.activationRequests, [sessionID])
            XCTAssertNil(handoff.boundSessionID)
        }
    }

    func testFocusNowHandsOffBeforeACompetingLocalWriterCanEndFocus() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            let writerAttempted = DispatchSemaphore(value: 0)
            let writerCompleted = DispatchSemaphore(value: 0)
            handoff.onActivation = {
                DispatchQueue.global().async {
                    writerAttempted.signal()
                    _ = try? store.update { engine in
                        try engine.apply(.stopFocus, now: Date())
                    }
                    writerCompleted.signal()
                }
                XCTAssertEqual(writerAttempted.wait(timeout: .now() + 1), .success)
                XCTAssertEqual(writerCompleted.wait(timeout: .now() + 0.1), .timedOut)
            }

            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "write the report"
            controller.start()
            let sessionID = try XCTUnwrap(controller.world.live?.id)

            controller.focusNow()

            XCTAssertEqual(handoff.activationRequests, [sessionID])
            XCTAssertEqual(writerCompleted.wait(timeout: .now() + 1), .success)
            XCTAssertEqual(try store.load().live?.phase, .onBreak)
        }
    }

    func testFocusNowStillTransitionsWhenNoWorkContextExists() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            handoff.hasCandidate = false
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "write the report"

            controller.start()
            controller.focusNow()

            XCTAssertEqual(controller.world.live?.phase, .focus)
            XCTAssertTrue(handoff.activationRequests.isEmpty)
            XCTAssertNil(handoff.boundSessionID)
        }
    }

    func testRecoveryRestartTransfersTheBoundWorkContext() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "write the report"
            controller.start()
            let originalID = try XCTUnwrap(controller.world.live?.id)

            XCTAssertTrue(controller.pauseForRecovery())
            controller.restartSession()

            let replacementID = try XCTUnwrap(controller.world.live?.id)
            XCTAssertNotEqual(replacementID, originalID)
            XCTAssertEqual(handoff.transfers.count, 1)
            XCTAssertEqual(handoff.transfers.first?.from, originalID)
            XCTAssertEqual(handoff.transfers.first?.to, replacementID)
            XCTAssertEqual(handoff.boundSessionID, replacementID)

            controller.focusNow()
            XCTAssertEqual(controller.world.live?.phase, .focus)
            XCTAssertEqual(handoff.activationRequests, [replacementID])
        }
    }

    func testStaleRecoveryContinueCannotResumeAReplacementSession() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "original task"
            controller.start()
            XCTAssertTrue(controller.pauseForRecovery())

            let winningWorld = try replaceWithPausedPrime(in: store)
            controller.continueSession()

            XCTAssertEqual(controller.world, winningWorld)
            XCTAssertEqual(try store.load(), winningWorld)
            XCTAssertTrue(controller.world.live?.isPaused == true)
            XCTAssertNil(handoff.boundSessionID)
            XCTAssertTrue(handoff.activationRequests.isEmpty)
        }
    }

    func testStaleRecoveryRestartCannotReplaceTheWinnerOrTransferWorkContext() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "original task"
            controller.start()
            XCTAssertTrue(controller.pauseForRecovery())

            let winningWorld = try replaceWithPausedPrime(in: store)
            controller.restartSession()

            XCTAssertEqual(controller.world, winningWorld)
            XCTAssertEqual(try store.load(), winningWorld)
            XCTAssertTrue(controller.world.live?.isPaused == true)
            XCTAssertNil(handoff.boundSessionID)
            XCTAssertTrue(handoff.transfers.isEmpty)
            XCTAssertTrue(handoff.activationRequests.isEmpty)
        }
    }

    func testAutomaticOrNonGesturePrimeAdvanceNeverActivatesWorkContext() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "write the report"

            controller.start()
            controller.skip()

            XCTAssertEqual(controller.world.live?.phase, .focus)
            XCTAssertTrue(handoff.activationRequests.isEmpty)
            XCTAssertNil(handoff.boundSessionID)
        }
    }

    func testFocusNowDoesNotActivateAnAppSelectedForFocusGuard() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            handoff.candidateBundleIdentifier = "com.example.Distraction"
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.addGuardedApp(bundleIdentifier: "com.example.Distraction")
            controller.intentionDraft = "write the report"

            controller.start()
            controller.focusNow()

            XCTAssertEqual(controller.world.live?.phase, .focus)
            XCTAssertTrue(handoff.activationRequests.isEmpty)
            XCTAssertNil(handoff.boundSessionID)
        }
    }

    func testStaleFocusNowCannotStopFocusStartedByAnotherSurface() throws {
        try withStore { store in
            let handoff = RecordingWorkContextHandoff()
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: handoff
            )
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "write the report"
            controller.start()

            _ = try store.update { engine in
                try engine.apply(.skip, now: Date())
            }
            XCTAssertEqual(controller.world.live?.phase, .prime)

            controller.focusNow()

            XCTAssertEqual(controller.world.live?.phase, .focus)
            XCTAssertEqual(try store.load().live?.phase, .focus)
            XCTAssertTrue(handoff.activationRequests.isEmpty)
            XCTAssertNil(handoff.boundSessionID)
        }
    }

    func testFocusSceneStartsExactFocusAsTransientLargeCanvasPresentation() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let handoff = RecordingWorkContextHandoff()
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: handoff,
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "write the report"
                controller.start()

                controller.startFocusScene()

                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertTrue(controller.isFocusSceneActive)
                XCTAssertEqual(controller.displayMode, .classic)
                XCTAssertFalse(controller.isPinned)
                XCTAssertTrue(handoff.activationRequests.isEmpty)
                XCTAssertNil(handoff.boundSessionID)
                XCTAssertEqual(defaults.string(forKey: "FlowmoDisplayMode"), DisplayMode.classic.rawValue)
            }
        }
    }

    func testLeavingFocusSceneKeepsExactFocusAndReturnsToFlowmoWindow() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let handoff = RecordingWorkContextHandoff()
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: handoff,
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "write the report"
                controller.start()
                let sessionID = try XCTUnwrap(controller.world.live?.id)
                controller.startFocusScene()

                controller.leaveFocusScene()

                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertTrue(handoff.activationRequests.isEmpty)
                XCTAssertNil(handoff.boundSessionID)
                XCTAssertEqual(controller.displayMode, .classic)
                XCTAssertFalse(controller.isPinned)
            }
        }
    }

    func testFocusSceneCanBeEnteredLeftAndReenteredDuringTheSameExactFocus() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let handoff = RecordingWorkContextHandoff()
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: handoff,
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.setDisplayMode(.mini)
                controller.togglePin()
                controller.intentionDraft = "write the report"
                controller.start()
                controller.skip()
                let sessionID = try XCTUnwrap(controller.world.live?.id)
                let phaseStartedAt = try XCTUnwrap(store.load().live?.phaseStartedAt)

                controller.enterFocusScene()

                XCTAssertTrue(controller.isFocusSceneActive)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertEqual(controller.world.live?.phaseStartedAt, phaseStartedAt)

                controller.leaveFocusScene()

                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.displayMode, .mini)
                XCTAssertTrue(controller.isPinned)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertEqual(controller.world.live?.phaseStartedAt, phaseStartedAt)

                controller.enterFocusScene()
                controller.leaveFocusScene()

                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertEqual(controller.world.live?.phaseStartedAt, phaseStartedAt)
                XCTAssertEqual(try store.load().live?.id, sessionID)
                XCTAssertEqual(try store.load().live?.phase, .focus)
                XCTAssertEqual(try store.load().live?.phaseStartedAt, phaseStartedAt)
                XCTAssertTrue(handoff.activationRequests.isEmpty)
                XCTAssertNil(handoff.boundSessionID)
            }
        }
    }

    func testStaleFocusSceneEntryCannotPresentAReplacementFocus() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "original task"
                controller.start()
                controller.skip()
                let originalID = try XCTUnwrap(controller.world.live?.id)

                let replacementStart = Date().addingTimeInterval(-1)
                let replacement = try store.update { engine in
                    try engine.apply(.cancel, now: replacementStart)
                    try engine.apply(
                        .start(intention: "replacement task"),
                        now: replacementStart.addingTimeInterval(0.1)
                    )
                    try engine.apply(.skip, now: replacementStart.addingTimeInterval(0.2))
                }
                let replacementID = try XCTUnwrap(replacement.world.live?.id)
                XCTAssertNotEqual(replacementID, originalID)

                controller.enterFocusScene()

                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.world.live?.id, replacementID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertEqual(try store.load().live?.id, replacementID)
                XCTAssertEqual(try store.load().live?.phase, .focus)
            }
        }
    }

    func testFocusSceneRestoresPriorPresentationWhenFocusEnds() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.setDisplayMode(.mini)
                controller.togglePin()
                controller.intentionDraft = "write the report"
                controller.start()
                controller.startFocusScene()

                controller.stopFocus()

                XCTAssertEqual(controller.world.live?.phase, .onBreak)
                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.displayMode, .mini)
                XCTAssertTrue(controller.isPinned)
            }
        }
    }

    func testManualExpandOrUnpinLeavesFocusSceneWithoutLaterSnapBack() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let first = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults
                )
                first.beginMacProcessLifetime()
                first.intentionDraft = "write the report"
                first.start()
                first.startFocusScene()

                first.setDisplayMode(.classic)

                XCTAssertFalse(first.isFocusSceneActive)
                XCTAssertEqual(first.displayMode, .classic)
                XCTAssertFalse(first.isPinned)
                first.stopFocus()
                XCTAssertEqual(first.displayMode, .classic)
                XCTAssertFalse(first.isPinned)
            }
        }

        try withStore { store in
            try withUserDefaults { defaults in
                let second = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults
                )
                second.beginMacProcessLifetime()
                second.intentionDraft = "write the report"
                second.start()
                second.startFocusScene()

                second.togglePin()

                XCTAssertFalse(second.isFocusSceneActive)
                XCTAssertEqual(second.displayMode, .classic)
                XCTAssertTrue(second.isPinned)
                second.stopFocus()
                XCTAssertEqual(second.displayMode, .classic)
                XCTAssertTrue(second.isPinned)
            }
        }
    }

    func testRecoveryPauseLeavesFocusSceneAndRestoresPresentation() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "write the report"
                controller.start()
                controller.startFocusScene()

                XCTAssertTrue(controller.pauseForRecovery())

                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertTrue(controller.world.live?.isPaused == true)
                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.displayMode, .classic)
                XCTAssertFalse(controller.isPinned)
            }
        }
    }

    func testStaleFocusSceneCannotPresentOrActivateAfterAnotherSurfaceEnteredFocus() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let handoff = RecordingWorkContextHandoff()
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: handoff,
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "write the report"
                controller.start()

                _ = try store.update { engine in
                    try engine.apply(.skip, now: start.addingTimeInterval(1))
                }

                controller.startFocusScene()

                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.displayMode, .classic)
                XCTAssertFalse(controller.isPinned)
                XCTAssertTrue(handoff.activationRequests.isEmpty)
            }
        }
    }

    func testStaleFocusSceneLeaveNeverMutatesSessionOrActivatesAnotherApp() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let handoff = RecordingWorkContextHandoff()
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: handoff,
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "write the report"
                controller.start()
                controller.startFocusScene()

                _ = try store.update { engine in
                    try engine.apply(.stopFocus, now: start.addingTimeInterval(60))
                }

                controller.leaveFocusScene()

                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertTrue(handoff.activationRequests.isEmpty)
                XCTAssertNil(handoff.boundSessionID)
                XCTAssertEqual(try store.load().live?.phase, .onBreak)
            }
        }
    }

    func testStaleFocusSceneStopCannotEndAReplacementFocus() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "original task"
                controller.start()
                controller.startFocusScene()
                let originalID = try XCTUnwrap(controller.world.live?.id)

                let replacementStart = Date().addingTimeInterval(-1)
                let replacement = try store.update { engine in
                    try engine.apply(.cancel, now: replacementStart)
                    try engine.apply(
                        .start(intention: "replacement task"),
                        now: replacementStart.addingTimeInterval(0.1)
                    )
                    try engine.apply(.skip, now: replacementStart.addingTimeInterval(0.2))
                }
                let replacementID = try XCTUnwrap(replacement.world.live?.id)
                XCTAssertNotEqual(replacementID, originalID)
                XCTAssertEqual(replacement.world.live?.phase, .focus)

                controller.stopFocus()

                XCTAssertEqual(controller.world.live?.id, replacementID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertEqual(try store.load().live?.id, replacementID)
                XCTAssertEqual(try store.load().live?.phase, .focus)
                XCTAssertFalse(controller.isFocusSceneActive)
            }
        }
    }

    func testLifecycleBlockerDiscardsFocusSceneWithoutResurrectionOnRetry() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "write the report"
                controller.start()
                controller.startFocusScene()
                let sessionID = try XCTUnwrap(controller.world.live?.id)
                XCTAssertTrue(controller.isFocusSceneActive)

                let markerURL = store.root.appendingPathComponent("mac-process-recovery.json")
                try FileManager.default.removeItem(at: markerURL)
                try FileManager.default.createDirectory(
                    at: markerURL,
                    withIntermediateDirectories: false
                )

                controller.setCuesEnabled(!controller.world.config.cuesEnabled)

                XCTAssertTrue(controller.lifecycleNeedsRecovery)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertFalse(controller.isFocusSceneActive)

                try FileManager.default.removeItem(at: markerURL)
                controller.retryLifecycleRecovery()

                XCTAssertFalse(controller.lifecycleNeedsRecovery)
                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
            }
        }
    }

    func testStoreBlockerDiscardsFocusSceneWithoutResurrectionOnRetry() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "write the report"
                controller.start()
                controller.startFocusScene()
                let sessionID = try XCTUnwrap(controller.world.live?.id)
                XCTAssertTrue(controller.isFocusSceneActive)

                let worldURL = store.worldURL
                let backupURL = store.root.appendingPathComponent("world-backup-for-scene-test.json")
                try FileManager.default.moveItem(at: worldURL, to: backupURL)
                try FileManager.default.createDirectory(
                    at: worldURL,
                    withIntermediateDirectories: false
                )

                controller.setCuesEnabled(!controller.world.config.cuesEnabled)

                XCTAssertTrue(controller.storeNeedsRecovery)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
                XCTAssertFalse(controller.isFocusSceneActive)

                try FileManager.default.removeItem(at: worldURL)
                try FileManager.default.moveItem(at: backupURL, to: worldURL)
                controller.retryStore()

                XCTAssertFalse(controller.storeNeedsRecovery)
                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
            }
        }
    }

    func testSyncConflictDiscardsFocusSceneWithoutResurrectionWhenConflictClears() throws {
        try withStore { store in
            try withUserDefaults { defaults in
                let syncStatus = WorldSyncStatus()
                let controller = FlowmoSessionController(
                    store: store,
                    attention: AttentionAdapter(canNotify: false),
                    workContextHandoff: RecordingWorkContextHandoff(),
                    userDefaults: defaults,
                    syncStatus: syncStatus
                )
                controller.beginMacProcessLifetime()
                controller.intentionDraft = "write the report"
                controller.start()
                controller.startFocusScene()
                let sessionID = try XCTUnwrap(controller.world.live?.id)
                XCTAssertTrue(controller.isFocusSceneActive)

                let local = WorldSyncSnapshot(world: controller.world, generation: UUID())
                let remote = WorldSyncSnapshot(world: controller.world, generation: UUID())
                syncStatus.update(
                    phase: .needsChoice,
                    conflict: WorldSyncConflict(
                        kind: .liveSession,
                        local: local,
                        remote: remote,
                        ancestor: nil
                    )
                )

                XCTAssertNotNil(syncStatus.conflict)
                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)

                syncStatus.update(phase: .synced)

                XCTAssertNil(syncStatus.conflict)
                XCTAssertFalse(controller.isFocusSceneActive)
                XCTAssertEqual(controller.world.live?.id, sessionID)
                XCTAssertEqual(controller.world.live?.phase, .focus)
            }
        }
    }

    func testSelectedHistorySessionFillsDraftWithoutStartingOrPersisting() throws {
        try withStore { store in
            let session = CompletedSession(
                id: UUID(),
                intention: "write the report",
                focusSeconds: 600,
                breakSeconds: 120,
                captureCount: 0,
                recallText: "finish the conclusion",
                endedAt: start
            )
            var world = World.empty
            world.history = [session]
            try store.save(world)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))

            XCTAssertTrue(controller.resumeCompletedSession(session))
            XCTAssertEqual(controller.intentionDraft, "finish the conclusion")
            XCTAssertNil(controller.world.live)
            XCTAssertEqual(try store.load(), world)
        }
    }

    func testCloseDoneCarriesExactNextStepIntoEditableIdleWithoutStarting() throws {
        try withStore { store in
            let sessionID = try saveCloseBeatSession(
                to: store,
                recallText: "  finish the conclusion \n"
            )
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: RecordingWorkContextHandoff()
            )
            controller.beginMacProcessLifetime()

            controller.dismissCloseBeat()

            XCTAssertNil(controller.world.live)
            XCTAssertEqual(controller.intentionDraft, "finish the conclusion")
            XCTAssertEqual(controller.world.history.last?.id, sessionID)
            XCTAssertEqual(try store.load(), controller.world)

            controller.intentionDraft = "finish and proofread the conclusion"
            controller.start()
            XCTAssertEqual(controller.world.live?.phase, .prime)
            XCTAssertEqual(
                controller.world.live?.intention,
                "finish and proofread the conclusion"
            )
        }
    }

    func testCloseDoneWithBlankNextStepNeverFallsBackToOlderWork() throws {
        try withStore { store in
            let older = CompletedSession(
                id: UUID(),
                intention: "older task",
                focusSeconds: 600,
                breakSeconds: 120,
                captureCount: 0,
                recallText: "do not carry this",
                endedAt: start.addingTimeInterval(-100)
            )
            _ = try saveCloseBeatSession(
                to: store,
                recallText: " \n ",
                history: [older]
            )
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: RecordingWorkContextHandoff()
            )
            controller.beginMacProcessLifetime()

            controller.dismissCloseBeat()

            XCTAssertNil(controller.world.live)
            XCTAssertTrue(controller.intentionDraft.isEmpty)
            XCTAssertNil(NextStepSuggestion.latest(in: controller.world.history))
        }
    }

    func testStaleCloseDoneCannotAdvanceOrBridgeAReplacementSession() throws {
        try withStore { store in
            _ = try saveCloseBeatSession(to: store, recallText: "stale next step")
            let controller = FlowmoSessionController(
                store: store,
                attention: AttentionAdapter(canNotify: false),
                workContextHandoff: RecordingWorkContextHandoff()
            )
            controller.beginMacProcessLifetime()

            _ = try store.update { engine in
                try engine.apply(.skip, now: start.addingTimeInterval(64))
                try engine.apply(
                    .start(intention: "replacement task"),
                    now: start.addingTimeInterval(65)
                )
            }

            controller.dismissCloseBeat()

            XCTAssertEqual(controller.world.live?.phase, .prime)
            XCTAssertEqual(controller.world.live?.intention, "replacement task")
            XCTAssertEqual(try store.load().live?.phase, .prime)
            XCTAssertTrue(controller.intentionDraft.isEmpty)
        }
    }

    func testSelectedHistorySessionRequiresExplicitReplacementOfTypedDraft() throws {
        try withStore { store in
            let session = CompletedSession(
                id: UUID(),
                intention: "write the report",
                focusSeconds: 600,
                breakSeconds: 120,
                captureCount: 0,
                recallText: "finish the conclusion",
                endedAt: start
            )
            var world = World.empty
            world.history = [session]
            try store.save(world)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.intentionDraft = "keep this draft"

            XCTAssertFalse(controller.resumeCompletedSession(session))
            XCTAssertEqual(controller.intentionDraft, "keep this draft")
            XCTAssertTrue(
                controller.resumeCompletedSession(session, replacingCurrentDraft: true)
            )
            XCTAssertEqual(controller.intentionDraft, "finish the conclusion")
            XCTAssertEqual(try store.load(), world)
        }
    }

    func testPromotingParkedThoughtDuringReflectionPersistsNextStepAndKeepsCapture() throws {
        try withStore { store in
            try saveReflectionSession(to: store)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.beginMacProcessLifetime()
            XCTAssertEqual(controller.world.live?.phase, .recall)
            let capture = try XCTUnwrap(controller.world.live?.captures.first)

            XCTAssertTrue(controller.useParkedThoughtAsNext(capture))
            XCTAssertEqual(controller.recallDraft, "review the evidence")
            XCTAssertEqual(controller.world.live?.recallText, "review the evidence")
            XCTAssertEqual(controller.world.live?.captures, [capture])

            let persisted = try store.load()
            XCTAssertEqual(persisted.live?.recallText, "review the evidence")
            XCTAssertEqual(persisted.live?.captures, [capture])
        }
    }

    func testParkedPromotionPreservesTypedAndStoredRecallAndRejectsForeignCapture() throws {
        try withStore { store in
            try saveReflectionSession(to: store)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.beginMacProcessLifetime()
            XCTAssertEqual(controller.world.live?.phase, .recall)
            let capture = try XCTUnwrap(controller.world.live?.captures.first)
            let foreignCapture = CaptureItem(text: "not in this session", createdAt: start)

            XCTAssertFalse(controller.useParkedThoughtAsNext(foreignCapture))
            XCTAssertEqual(controller.world.live?.recallText, "")
            XCTAssertEqual(controller.world.live?.captures, [capture])

            controller.recallDraft = "typed next step"
            XCTAssertFalse(controller.useParkedThoughtAsNext(capture))
            XCTAssertEqual(controller.recallDraft, "typed next step")
            XCTAssertEqual(controller.world.live?.recallText, "")
            XCTAssertEqual(controller.world.live?.captures, [capture])

            controller.recallDraft = "saved next step"
            controller.persistRecall()
            XCTAssertFalse(controller.useParkedThoughtAsNext(capture))
            XCTAssertEqual(controller.recallDraft, "saved next step")
            XCTAssertEqual(controller.world.live?.recallText, "saved next step")
            XCTAssertEqual(controller.world.live?.captures, [capture])
            XCTAssertEqual(try store.load().live?.recallText, "saved next step")
        }
    }

    func testParkedPromotionDoesNotOverwriteRecallSavedByAnotherSurface() throws {
        try withStore { store in
            try saveReflectionSession(to: store)
            let controller = FlowmoSessionController(store: store, attention: AttentionAdapter(canNotify: false))
            controller.beginMacProcessLifetime()
            let capture = try XCTUnwrap(controller.world.live?.captures.first)

            _ = try store.update { engine in
                try engine.apply(.setRecallText("saved elsewhere"), now: start.addingTimeInterval(62))
            }

            XCTAssertFalse(controller.useParkedThoughtAsNext(capture))
            XCTAssertEqual(controller.recallDraft, "saved elsewhere")
            XCTAssertEqual(controller.world.live?.recallText, "saved elsewhere")
            XCTAssertEqual(try store.load().live?.recallText, "saved elsewhere")
            XCTAssertEqual(controller.world.live?.captures, [capture])
        }
    }

    private func saveReflectionSession(to store: Store) throws {
        var engine = Engine()
        try engine.apply(.start(intention: "write the report"), now: start)
        try engine.apply(.skip, now: start)
        try engine.apply(.capture("review the evidence"), now: start.addingTimeInterval(1))
        try engine.apply(.stopFocus, now: start.addingTimeInterval(60))
        try engine.apply(.skip, now: start.addingTimeInterval(61))
        try store.save(engine.world)
    }

    private func replaceWithPausedPrime(in store: Store) throws -> World {
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)
        return try store.update { engine in
            try engine.apply(.restart, now: timestamp)
            try engine.apply(.pauseForRecovery, now: timestamp.addingTimeInterval(1))
        }.world
    }

    @discardableResult
    private func saveCloseBeatSession(
        to store: Store,
        recallText: String,
        history: [CompletedSession] = []
    ) throws -> UUID {
        var world = World.empty
        world.history = history
        var engine = Engine(world: world)
        try engine.apply(.start(intention: "write the report"), now: start)
        try engine.apply(.skip, now: start.addingTimeInterval(1))
        try engine.apply(.stopFocus, now: start.addingTimeInterval(60))
        try engine.apply(.skip, now: start.addingTimeInterval(61))
        try engine.apply(.setRecallText(recallText), now: start.addingTimeInterval(62))
        try engine.apply(.skip, now: start.addingTimeInterval(63))
        let sessionID = try XCTUnwrap(engine.world.live?.id)
        try store.save(engine.world)
        return sessionID
    }

    private func withStore(_ body: (Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowmo-window-continuity-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Store(root: root))
    }

    private func withUserDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "flowmo-focus-scene-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(DisplayMode.classic.rawValue, forKey: "FlowmoDisplayMode")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}

@MainActor
private final class RecordingWorkContextHandoff: WorkContextHandoff {
    struct Transfer: Equatable {
        let from: UUID
        let to: UUID
    }

    var hasCandidate = true
    var candidateBundleIdentifier = "com.example.Work"
    var onActivation: (() -> Void)?
    private(set) var boundSessionID: UUID?
    private(set) var activationRequests: [UUID] = []
    private(set) var transfers: [Transfer] = []

    func bindCandidate(to sessionID: UUID) {
        boundSessionID = hasCandidate ? sessionID : nil
    }

    func activateBoundTarget(
        for sessionID: UUID,
        excludingBundleIdentifiers: Set<String>
    ) {
        guard boundSessionID == sessionID else { return }
        guard !excludingBundleIdentifiers.contains(candidateBundleIdentifier) else { return }
        onActivation?()
        activationRequests.append(sessionID)
    }

    func transferBoundTarget(from oldSessionID: UUID, to newSessionID: UUID) {
        guard boundSessionID == oldSessionID else { return }
        transfers.append(Transfer(from: oldSessionID, to: newSessionID))
        boundSessionID = newSessionID
    }

    func retainOnly(sessionID: UUID?) {
        guard boundSessionID != sessionID else { return }
        boundSessionID = nil
    }
}
