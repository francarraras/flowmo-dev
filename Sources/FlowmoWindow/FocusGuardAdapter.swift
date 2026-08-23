import AppKit
import Combine
import FlowmoCore

private func processIdentity(
    for application: NSRunningApplication
) -> FocusGuardProcessIdentity? {
    guard let bundleIdentifier = application.bundleIdentifier,
        let launchDate = application.launchDate
    else { return nil }
    return FocusGuardProcessIdentity(
        processIdentifier: application.processIdentifier,
        bundleIdentifier: bundleIdentifier,
        launchDate: launchDate
    )
}

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
        let previousGeneration = runtime.demandGeneration
        var next = runtime
        next.setDemand(FocusGuard.demand(world: world))
        runtime = next
        switch runtime.demand {
        case .inactive:
            stopObserving()
        case .active:
            startObserving()
            if runtime.demandGeneration != previousGeneration {
                evaluateFrontmostApplication()
            }
        }
    }

    public func stayFocused() {
        var next = runtime
        next.stayFocused()
        runtime = next
    }

    public func openOnce() {
        guard let work = runtime.currentWork else { return }
        guard resolve(work.processIdentity) != nil else {
            failOpen(work)
            return
        }

        var next = runtime
        next.allowOnce()
        runtime = next

        guard let app = resolve(work.processIdentity) else {
            failOpenAllowedProcess(work.processIdentity)
            return
        }
        _ = app.unhide()
        guard let app = resolve(work.processIdentity),
            app.activate(options: [.activateIgnoringOtherApps])
        else {
            failOpenAllowedProcess(work.processIdentity)
            return
        }
        runtime.degraded = false
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
                let identity = app.flatMap(processIdentity(for:))
                let name = app?.localizedName ?? identity?.bundleIdentifier ?? "App"
                let isSelf = app == .current
                Task { @MainActor in
                    guard let identity else { return }
                    self?.handleActivation(
                        processIdentity: identity,
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
                let identity = app.flatMap(processIdentity(for:))
                Task { @MainActor in
                    guard let identity else { return }
                    self?.handleDeactivation(processIdentity: identity)
                }
            }
        )
        observing = true
    }

    private func evaluateFrontmostApplication() {
        if let app = NSWorkspace.shared.frontmostApplication,
            let identity = processIdentity(for: app)
        {
            handleActivation(
                processIdentity: identity,
                displayName: app.localizedName ?? identity.bundleIdentifier,
                isSelf: app == .current
            )
        }
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
        processIdentity: FocusGuardProcessIdentity,
        displayName: String,
        isSelf: Bool
    ) {
        let selfID = ownBundleIDs.contains(processIdentity.bundleIdentifier)
        var next = runtime
        let decision = next.activated(
            processIdentity: processIdentity,
            displayName: displayName,
            isSelf: isSelf || selfID
        )
        switch decision {
        case .ignore, .allowedOnce:
            runtime = next
        case .intercept:
            runtime = next
            guard let work = runtime.currentWork else { return }
            hideGuardedApp(work)
        }
    }

    private func hideGuardedApp(_ work: FocusGuardWork, attempt: Int = 0) {
        guard runtime.isCurrent(work) else { return }
        guard let app = resolve(work.processIdentity) else {
            failOpen(work)
            return
        }
        _ = app.hide()

        guard runtime.isCurrent(work) else { return }
        guard let app = resolve(work.processIdentity) else {
            failOpen(work)
            return
        }
        if app.isHidden {
            runtime.degraded = false
            bringForward()
            return
        }
        if attempt < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.hideGuardedApp(work, attempt: attempt + 1)
            }
            return
        }
        failOpen(work)
    }

    private func failOpen(_ work: FocusGuardWork) {
        guard runtime.isCurrent(work) else { return }
        var next = runtime
        next.degraded = true
        next.interception = nil
        runtime = next
    }

    private func failOpenAllowedProcess(_ identity: FocusGuardProcessIdentity) {
        guard runtime.allowedProcessIdentity == identity else { return }
        var next = runtime
        next.allowedProcessIdentity = nil
        next.degraded = true
        runtime = next
    }

    private func resolve(
        _ identity: FocusGuardProcessIdentity
    ) -> NSRunningApplication? {
        guard
            let app = NSRunningApplication(
                processIdentifier: identity.processIdentifier
            ), processIdentity(for: app) == identity
        else { return nil }
        return app
    }

    private func handleDeactivation(processIdentity: FocusGuardProcessIdentity) {
        var next = runtime
        next.deactivated(processIdentity: processIdentity)
        runtime = next
    }
}
