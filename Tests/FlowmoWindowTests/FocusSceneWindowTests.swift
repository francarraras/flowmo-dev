import AppKit
import FlowmoCore
import SwiftUI
import XCTest

@testable import FlowmoWindow

@MainActor
final class FocusSceneWindowTests: XCTestCase {
    func testSceneEntryControlIsDirectAndOnlyAvailableForAnUnpausedFocus() {
        XCTAssertEqual(FocusSceneEntryControl.title, "Focus scene")
        XCTAssertEqual(FocusSceneEntryControl.compactTitle, "Scene")
        XCTAssertTrue(FocusSceneEntryControl.isAvailable(phase: .focus, isPaused: false))
        XCTAssertFalse(FocusSceneEntryControl.isAvailable(phase: .focus, isPaused: true))
        XCTAssertFalse(FocusSceneEntryControl.isAvailable(phase: .prime, isPaused: false))
        XCTAssertFalse(FocusSceneEntryControl.isAvailable(phase: .onBreak, isPaused: false))
        XCTAssertFalse(FocusSceneEntryControl.isAvailable(phase: nil, isPaused: false))
        XCTAssertEqual(FocusSceneEntryControl.accessibilityLabel, "Open Focus Scene")
        XCTAssertEqual(
            FocusSceneEntryControl.accessibilityHint,
            "Opens the same Focus in Scene. The menu also offers Focus Scene and window sizes."
        )
    }

    func testScenePresentationIsSuppressedForEveryBlockingRecoveryOrConflictState() {
        let presentation = FocusScenePresentation(
            sessionID: UUID(),
            previousDisplayMode: .classic,
            previousPinned: false
        )

        XCTAssertTrue(
            AppDelegate.shouldPresentFocusScene(
                presentation: presentation,
                storeNeedsRecovery: false,
                lifecycleNeedsRecovery: false,
                hasSyncConflict: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentFocusScene(
                presentation: presentation,
                storeNeedsRecovery: true,
                lifecycleNeedsRecovery: false,
                hasSyncConflict: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentFocusScene(
                presentation: presentation,
                storeNeedsRecovery: false,
                lifecycleNeedsRecovery: true,
                hasSyncConflict: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentFocusScene(
                presentation: presentation,
                storeNeedsRecovery: false,
                lifecycleNeedsRecovery: false,
                hasSyncConflict: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentFocusScene(
                presentation: nil,
                storeNeedsRecovery: false,
                lifecycleNeedsRecovery: false,
                hasSyncConflict: false
            )
        )
    }

    func testSceneUsesTheExistingKeyCapableWindowAndRestoresEveryChangedProperty() throws {
        let originalFrame = NSRect(x: 180, y: 220, width: 320, height: 460)
        let originalMin = NSSize(width: 320, height: 460)
        let originalMax = NSSize(width: 320, height: 460)
        let originalBackground = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.06, alpha: 1)
        let window = SceneCapableWindow(
            contentRect: originalFrame,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Flowmo"
        window.level = .floating
        window.contentMinSize = originalMin
        window.contentMaxSize = originalMax
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.backgroundColor = originalBackground
        let originalWindowFrame = window.frame
        let originalStyleMask = window.styleMask
        let coordinator = FocusSceneWindowCoordinator(window: window)

        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)

        coordinator.present()

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(window.styleMask, [.borderless, .resizable])
        XCTAssertEqual(window.title, "Flowmo Focus Scene")
        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.hasShadow)
        XCTAssertEqual(window.contentMinSize, NSSize(width: 720, height: 480))
        XCTAssertNotEqual(window.contentMinSize, window.contentMaxSize)

        coordinator.restore()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(window.frame, originalWindowFrame)
        XCTAssertEqual(window.styleMask, originalStyleMask)
        XCTAssertEqual(window.title, "Flowmo")
        XCTAssertEqual(window.level, .floating)
        XCTAssertEqual(window.contentMinSize, originalMin)
        XCTAssertEqual(window.contentMaxSize, originalMax)
        XCTAssertTrue(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.isOpaque)
        XCTAssertTrue(window.hasShadow)
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertEqual(window.backgroundColor, originalBackground)
    }

    func testScenePresentationAndRestoreAreIdempotent() {
        let window = SceneCapableWindow(
            contentRect: NSRect(x: 80, y: 100, width: 320, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let coordinator = FocusSceneWindowCoordinator(window: window)

        coordinator.present()
        let sceneFrame = window.frame
        coordinator.present()
        XCTAssertEqual(window.frame, sceneFrame)

        coordinator.restore()
        let restoredFrame = window.frame
        coordinator.restore()
        XCTAssertEqual(window.frame, restoredFrame)
    }

    func testSceneKeepsCommandWCloseRoutableWithoutANativeCloseButton() {
        let window = SceneCapableWindow(
            contentRect: NSRect(x: 80, y: 100, width: 320, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        var requestCount = 0
        window.sceneCloseHandler = {
            requestCount += 1
            return true
        }
        let coordinator = FocusSceneWindowCoordinator(window: window)

        coordinator.present()
        window.performClose(nil)

        XCTAssertEqual(requestCount, 1)
    }

    func testSceneStartsLargeButWindowedAndClampsBackOntoItsDisplay() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1_600, height: 1_000)

        let initial = FocusSceneWindowCoordinator.initialFrame(in: visibleFrame)

        XCTAssertGreaterThanOrEqual(initial.width, 720)
        XCTAssertGreaterThanOrEqual(initial.height, 480)
        XCTAssertLessThan(initial.width, visibleFrame.width)
        XCTAssertLessThan(initial.height, visibleFrame.height)
        XCTAssertEqual(initial.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(initial.midY, visibleFrame.midY, accuracy: 0.001)

        let offscreen = NSRect(x: 1_650, y: 920, width: 900, height: 700)
        let clamped = FocusSceneWindowCoordinator.clampedFrame(offscreen, within: visibleFrame)

        XCTAssertGreaterThanOrEqual(clamped.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(clamped.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(clamped.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(clamped.maxY, visibleFrame.maxY)
        XCTAssertEqual(clamped.size, offscreen.size)
    }

    func testSceneDragMathMatchesSwiftUIAndAppKitCoordinateDirections() {
        XCTAssertEqual(
            FocusSceneWindowDrag.origin(
                from: NSPoint(x: 100, y: 200),
                translation: CGSize(width: 30, height: 40)
            ),
            NSPoint(x: 130, y: 160)
        )
    }

    func testRootHostingViewNeverConsumesControlClicksAsWindowDrags() {
        let window = SceneCapableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        let hosting = FlowmoHostingView(rootView: EmptyView())
        window.contentView = hosting

        window.isMovableByWindowBackground = true
        XCTAssertFalse(hosting.mouseDownCanMoveWindow)
    }
}
