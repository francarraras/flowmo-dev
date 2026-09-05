import AppKit
import FlowmoCore
import Foundation
import XCTest

@testable import FlowmoWindow

@MainActor
final class MacMainMenuTests: XCTestCase {
    func testStandardCommandsUseNativeTargetsAndEditingResponderChain() throws {
        try withController { controller, _ in
            let application = NSApplication.shared
            let oldMain = application.mainMenu
            let oldWindows = application.windowsMenu
            defer {
                application.mainMenu = oldMain
                application.windowsMenu = oldWindows
            }
            let delegate = AppDelegate(controller: controller)
            MacMainMenu.install(on: application, delegate: delegate)
            let main = try XCTUnwrap(application.mainMenu)
            let appMenu = try XCTUnwrap(main.item(withTitle: "Flowmo")?.submenu)
            let quit = try XCTUnwrap(appMenu.item(withTitle: "Quit Flowmo"))
            XCTAssertEqual(quit.action, #selector(NSApplication.terminate(_:)))
            XCTAssertTrue(quit.target === application)
            XCTAssertEqual(quit.keyEquivalent, "q")
            XCTAssertEqual(quit.keyEquivalentModifierMask, .command)
            let hide = try XCTUnwrap(appMenu.item(withTitle: "Hide Flowmo"))
            XCTAssertEqual(hide.action, #selector(NSApplication.hide(_:)))
            XCTAssertTrue(hide.target === application)
            XCTAssertEqual(hide.keyEquivalent, "h")

            let edit = try XCTUnwrap(main.item(withTitle: "Edit")?.submenu)
            for (title, selector, key) in [
                ("Undo", "undo:", "z"), ("Redo", "redo:", "z"),
                ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
            ] {
                let item = try XCTUnwrap(edit.item(withTitle: title))
                XCTAssertNil(item.target, "\(title) must follow the current editor's responder chain.")
                XCTAssertEqual(item.action, NSSelectorFromString(selector))
                XCTAssertEqual(item.keyEquivalent, key)
                XCTAssertEqual(item.keyEquivalentModifierMask, title == "Redo" ? [.command, .shift] : .command)
            }

            let windowMenu = try XCTUnwrap(application.windowsMenu)
            let close = try XCTUnwrap(windowMenu.item(withTitle: "Close"))
            XCTAssertEqual(close.keyEquivalent, "w")
            XCTAssertEqual(close.action, #selector(AppDelegate.closeMainWindow(_:)))
            XCTAssertTrue(close.target === delegate)
            XCTAssertFalse(delegate.validateMenuItem(close))
            let window = SceneCapableWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            var guardedCloseCalls = 0
            window.sceneCloseHandler = {
                guardedCloseCalls += 1
                return true
            }
            delegate.window = window
            XCTAssertTrue(application.sendAction(try XCTUnwrap(close.action), to: close.target, from: close))
            XCTAssertEqual(guardedCloseCalls, 1, "Menu Close must preserve the Scene's existing interception.")
            let minimize = try XCTUnwrap(windowMenu.item(withTitle: "Minimize"))
            XCTAssertNil(minimize.target)
            XCTAssertEqual(minimize.action, #selector(NSWindow.performMiniaturize(_:)))
            XCTAssertEqual(minimize.keyEquivalent, "m")
        }
    }

    func testApplicationTerminationCommitsRecoveryAndReopenDoesNotResume() throws {
        try withController { controller, store in
            controller.beginMacProcessLifetime()
            controller.intentionDraft = "native quit proof"
            controller.start()
            controller.skip()
            let sessionID = try XCTUnwrap(store.load().live?.id)
            let delegate = AppDelegate(controller: controller)

            XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)

            let paused = try store.load()
            XCTAssertEqual(paused.live?.id, sessionID)
            XCTAssertEqual(paused.live?.phase, .focus)
            XCTAssertTrue(try XCTUnwrap(paused.live).isPaused)
            XCTAssertTrue(paused.history.isEmpty)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: store.root.appendingPathComponent("mac-process-recovery.json").path))
            XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
            XCTAssertEqual(try store.load(), paused)
        }
    }

    private func withController(_ body: (FlowmoSessionController, Store) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "flowmo-menu-proof-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        let preferencesName = "flowmo-menu-proof-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let controller = FlowmoSessionController(
            store: store, attention: AttentionAdapter(canNotify: false), userDefaults: preferences)
        try body(controller, store)
    }
}
