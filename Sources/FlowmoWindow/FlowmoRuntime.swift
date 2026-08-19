import AppKit
import Darwin
import SwiftUI

/// Hosts the compact window. `swift run` and the Xcode Dock app both call this entry.
@MainActor
public enum FlowmoRuntime {
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var retained: AppDelegate?

    let controller = FlowmoSessionController()
    var window: NSWindow?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.startRunning()
        let window = makeWindow()
        self.window = window
        controller.attention.window = window
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watchSleep()
        watchTerminationSignals()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.pauseForRecovery()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    @objc func macWillSleep(_ notification: Notification) {
        controller.pauseForRecovery()
    }

    private func watchSleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(macWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(macWillSleep),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }

    /// `swift run` is often stopped with Ctrl+C; treat that as quit (recovery pause).
    private func watchTerminationSignals() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        for sig in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.controller.pauseForRecovery()
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: FlowmoRootView(controller: controller))
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Flowmo"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.contentView = hosting
        window.setContentSize(NSSize(width: 300, height: 300))
        window.contentMinSize = NSSize(width: 260, height: 260)
        window.contentMaxSize = NSSize(width: 400, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .normal
        window.hidesOnDeactivate = false
        return window
    }
}
