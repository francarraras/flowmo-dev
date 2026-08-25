import AppKit
import Combine
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

    let controller: FlowmoSessionController
    var window: NSWindow?
    private let glance = StatusGlance()
    private var signalSources: [DispatchSourceSignal] = []
    private var modeCancellables = Set<AnyCancellable>()

    init(controller: FlowmoSessionController = FlowmoSessionController()) {
        self.controller = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = makeWindow()
        self.window = window
        controller.attention.window = window
        window.delegate = self
        controller.startRunning()
        glance.attach(controller: controller) { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        observeWindowContentSize()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        watchSleep()
        watchTerminationSignals()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.prepareForTermination()
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

    /// `swift run` is often stopped with Ctrl+C; route it through the same
    /// termination owner as a normal app quit.
    private func watchTerminationSignals() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        for sig in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Both modes are fixed-size. Free resizing is gone on purpose: every
    /// pane is laid out against these exact bounds.
    func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: FlowmoRootView(controller: controller))
        let size = controller.effectiveWindowContentSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Flowmo"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 10 / 255, green: 11 / 255, blue: 13 / 255, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.contentView = hosting
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .normal
        window.hidesOnDeactivate = false
        return window
    }

    /// Observe every published input to `effectiveWindowContentSize`. Keeping
    /// this binding beside the computed size prevents recovery-only changes
    /// from leaving the fixed NSWindow at its previous dimensions.
    func observeWindowContentSize() {
        Publishers.CombineLatest3(
            controller.$displayMode,
            controller.$storeNeedsRecovery,
            controller.$lifecycleNeedsRecovery
        )
        .map { mode, storeNeedsRecovery, lifecycleNeedsRecovery in
            FlowmoSessionController.windowContentSize(
                displayMode: mode,
                storeNeedsRecovery: storeNeedsRecovery,
                lifecycleNeedsRecovery: lifecycleNeedsRecovery
            )
        }
        .removeDuplicates()
        .sink { [weak self] size in
            self?.applyWindowMode(size)
        }
        .store(in: &modeCancellables)
    }

    /// Switches size without offering a resize grip. Equal min/max while
    /// `.resizable` is off makes AppKit ignore size changes, so unlock, size,
    /// lock. Top-left stays put.
    private func applyWindowMode(_ size: CGSize) {
        guard let window else { return }
        let pinnedTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.contentMinSize = NSSize(width: 1, height: 1)
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
        var mask = window.styleMask
        mask.insert(.resizable)
        window.styleMask = mask
        window.setContentSize(size)
        let frame = window.frame
        window.setFrameOrigin(NSPoint(x: pinnedTopLeft.x, y: pinnedTopLeft.y - frame.height))
        window.contentMinSize = size
        window.contentMaxSize = size
        mask.remove(.resizable)
        window.styleMask = mask
    }
}
