import AppKit
import Combine
import Darwin
import SwiftUI

/// The root host always keeps SwiftUI controls interactive. Focus Scene moves
/// the window with an explicit gesture attached only to its empty backdrop.
final class FlowmoHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

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
    private struct WindowPresentationState: Equatable {
        let contentSize: CGSize
        let focusSceneActive: Bool
    }

    static var retained: AppDelegate?

    let controller: FlowmoSessionController
    var window: NSWindow?
    private let glance = StatusGlance()
    private var signalSources: [DispatchSourceSignal] = []
    private var modeCancellables = Set<AnyCancellable>()
    private var focusSceneWindowCoordinator: FocusSceneWindowCoordinator?

    init(controller: FlowmoSessionController = FlowmoSessionController()) {
        self.controller = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = makeWindow()
        self.window = window
        window.sceneCloseHandler = { [weak self] in
            self?.closeFocusSceneFromCommand() ?? false
        }
        focusSceneWindowCoordinator = FocusSceneWindowCoordinator(window: window)
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
        watchScreenChanges()
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
        if controller.isFocusSceneActive,
            controller.focusGuard.runtime.interception != nil
        {
            NSSound.beep()
            return false
        }
        controller.leaveFocusScene()
        sender.orderOut(nil)
        return false
    }

    /// Borderless windows have no native close button, so Cmd-W enters here
    /// before AppKit's ordinary close path. A pending Guard decision still
    /// blocks the escape exactly like the window delegate path.
    private func closeFocusSceneFromCommand() -> Bool {
        guard controller.isFocusSceneActive else { return false }
        guard controller.focusGuard.runtime.interception == nil else {
            NSSound.beep()
            return true
        }
        controller.leaveFocusScene()
        window?.orderOut(nil)
        return true
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

    private func watchScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        focusSceneWindowCoordinator?.reflow()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        focusSceneWindowCoordinator?.reflow()
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

    /// Classic and Mini stay fixed-size. The same key-capable window can also
    /// become a large movable canvas while a transient Focus Scene is active.
    func makeWindow() -> SceneCapableWindow {
        let hosting = FlowmoHostingView(rootView: FlowmoRootView(controller: controller))
        let size = controller.effectiveWindowContentSize
        let window = SceneCapableWindow(
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
        let contentSize = Publishers.CombineLatest4(
            controller.$displayMode,
            controller.$storeNeedsRecovery,
            controller.$lifecycleNeedsRecovery,
            controller.syncStatus.$conflict
        )
        .combineLatest(controller.introduction.$isPresented)
        .map { inputs, showingIntroduction in
            let (mode, storeNeedsRecovery, lifecycleNeedsRecovery, conflict) = inputs
            return FlowmoSessionController.windowContentSize(
                displayMode: mode,
                storeNeedsRecovery: storeNeedsRecovery,
                lifecycleNeedsRecovery: lifecycleNeedsRecovery,
                hasSyncConflict: conflict != nil,
                showingIntroduction: showingIntroduction
            )
        }

        let focusSceneActive = Publishers.CombineLatest4(
            controller.$focusScenePresentation,
            controller.$storeNeedsRecovery,
            controller.$lifecycleNeedsRecovery,
            controller.syncStatus.$conflict
        )
        .map { presentation, storeNeedsRecovery, lifecycleNeedsRecovery, conflict in
            Self.shouldPresentFocusScene(
                presentation: presentation,
                storeNeedsRecovery: storeNeedsRecovery,
                lifecycleNeedsRecovery: lifecycleNeedsRecovery,
                hasSyncConflict: conflict != nil
            )
        }

        Publishers.CombineLatest(contentSize, focusSceneActive)
            .map { contentSize, focusSceneActive in
                WindowPresentationState(
                    contentSize: contentSize,
                    focusSceneActive: focusSceneActive
                )
            }
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self, let window = self.window else { return }
                if self.focusSceneWindowCoordinator == nil {
                    self.focusSceneWindowCoordinator = FocusSceneWindowCoordinator(window: window)
                }
                if state.focusSceneActive {
                    self.focusSceneWindowCoordinator?.present()
                } else {
                    self.focusSceneWindowCoordinator?.restore()
                    self.applyWindowMode(state.contentSize)
                }
            }
            .store(in: &modeCancellables)
    }

    static func shouldPresentFocusScene(
        presentation: FocusScenePresentation?,
        storeNeedsRecovery: Bool,
        lifecycleNeedsRecovery: Bool,
        hasSyncConflict: Bool
    ) -> Bool {
        presentation != nil
            && !storeNeedsRecovery
            && !lifecycleNeedsRecovery
            && !hasSyncConflict
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
        window.setFrameOrigin(
            Self.clampedWindowOrigin(
                pinnedTopLeft: pinnedTopLeft,
                windowSize: frame.size,
                visibleFrame: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            )
        )
        window.contentMinSize = size
        window.contentMaxSize = size
        mask.remove(.resizable)
        window.styleMask = mask
    }

    static func clampedWindowOrigin(
        pinnedTopLeft: NSPoint,
        windowSize: NSSize,
        visibleFrame: NSRect?
    ) -> NSPoint {
        var origin = NSPoint(
            x: pinnedTopLeft.x,
            y: pinnedTopLeft.y - windowSize.height
        )
        guard let visibleFrame else { return origin }
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        origin.x = min(max(origin.x, visibleFrame.minX), maximumX)
        origin.y = min(max(origin.y, visibleFrame.minY), maximumY)
        return origin
    }
}
