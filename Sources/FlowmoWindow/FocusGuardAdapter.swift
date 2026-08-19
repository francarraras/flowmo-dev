import AppKit
import Combine
import FlowmoCore

@MainActor
public final class FocusGuardAdapter: ObservableObject {
    @Published public private(set) var runtime = FocusGuardRuntime()
    @Published public private(set) var observing = false

    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var bringForward: () -> Void = {}
    private var ownBundleIDs: Set<String> = []

    public init() {}

    public func attach(bringForward: @escaping () -> Void) {
        self.bringForward = bringForward
        var ids = FocusGuard.forbiddenBundleIdentifiers
        if let mine = Bundle.main.bundleIdentifier {
            ids.insert(mine)
        }
        ownBundleIDs = ids
    }

    public func reconcile(world: World) {
        var next = runtime
        next.setDemand(FocusGuard.demand(world: world))
        runtime = next
        switch runtime.demand {
        case .inactive:
            stopObserving()
        case .active:
            startObserving()
        }
    }

    public func stayFocused() {
        var next = runtime
        next.stayFocused()
        runtime = next
    }

    public func openOnce() {
        var next = runtime
        let pid = next.interception?.processIdentifier
        next.allowOnce()
        runtime = next
        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.unhide()
            _ = app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                let bundleID = app?.bundleIdentifier
                let name = app?.localizedName ?? bundleID ?? "App"
                let isSelf = app == NSRunningApplication.current
                Task { @MainActor in
                    guard let pid else { return }
                    self?.handleActivation(
                        processID: pid,
                        bundleID: bundleID,
                        displayName: name,
                        isSelf: isSelf
                    )
                }
            }
        )
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.didDeactivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                Task { @MainActor in
                    guard let pid else { return }
                    self?.handleDeactivation(processID: pid)
                }
            }
        )
        observing = true
    }

    private func stopObserving() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspace.removeObserver(observer)
        }
        observers.removeAll()
        observing = false
    }

    private func handleActivation(
        processID: Int32,
        bundleID: String?,
        displayName: String,
        isSelf: Bool
    ) {
        let selfID = bundleID.map { ownBundleIDs.contains($0) } ?? false
        var next = runtime
        let decision = next.activated(
            bundleID: bundleID,
            processID: processID,
            displayName: displayName,
            isSelf: isSelf || selfID
        )
        switch decision {
        case .ignore, .allowedOnce:
            runtime = next
        case .intercept:
            runtime = next
            hideGuardedApp(processID: processID)
        }
    }

    private func hideGuardedApp(processID: Int32, attempt: Int = 0) {
        guard case .active = runtime.demand else { return }
        guard runtime.interception?.processIdentifier == processID else { return }
        guard let app = NSRunningApplication(processIdentifier: processID) else {
            failOpen()
            return
        }
        _ = app.hide()
        if app.isHidden {
            runtime.degraded = false
            bringForward()
            return
        }
        if attempt < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.hideGuardedApp(processID: processID, attempt: attempt + 1)
            }
            return
        }
        failOpen()
    }

    private func failOpen() {
        var next = runtime
        next.degraded = true
        next.interception = nil
        runtime = next
    }

    private func handleDeactivation(processID: Int32) {
        var next = runtime
        next.deactivated(processID: processID)
        runtime = next
    }
}
