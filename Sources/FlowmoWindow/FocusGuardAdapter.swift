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
protocol FocusGuardApplication: AnyObject {
    var focusGuardProcessIdentity: FocusGuardProcessIdentity? { get }
    var focusGuardIsHidden: Bool { get }
    func focusGuardHide() -> Bool
    func focusGuardUnhide() -> Bool
    func focusGuardActivate() -> Bool
}

extension NSRunningApplication: FocusGuardApplication {
    var focusGuardProcessIdentity: FocusGuardProcessIdentity? { processIdentity(for: self) }

    var focusGuardIsHidden: Bool { isHidden }

    func focusGuardHide() -> Bool { hide() }

    func focusGuardUnhide() -> Bool { unhide() }

    func focusGuardActivate() -> Bool {
        activate(options: [.activateIgnoringOtherApps])
    }
}

@MainActor
public final class FocusGuardAdapter: ObservableObject {
    static let resumptionConfirmationTimeout: TimeInterval = 1

    @Published public private(set) var runtime = FocusGuardRuntime()
    @Published public private(set) var observing = false
    @Published public private(set) var resumptionTreatmentEnabled = true

    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var bringForward: () -> Void = {}
    private var observeEvidence: (FocusGuardEvidenceEvent) -> Void = { _ in }
    private var ownBundleIDs: Set<String> = []
    private let resolveApplication: (FocusGuardProcessIdentity) -> (any FocusGuardApplication)?
    private var pendingResumption: PendingResumption?
    private var resumptionTimeoutTask: Task<Void, Never>?

    private struct PendingResumption {
        let id: UUID
        let processIdentity: FocusGuardProcessIdentity
    }

    public init() {
        self.resolveApplication = { identity in
            NSRunningApplication(processIdentifier: identity.processIdentifier)
        }
    }

    init(
        resolveApplication: @escaping (FocusGuardProcessIdentity) -> (any FocusGuardApplication)?
    ) {
        self.resolveApplication = resolveApplication
    }

    public func attach(
        bringForward: @escaping () -> Void,
        observeEvidence: @escaping (FocusGuardEvidenceEvent) -> Void = { _ in }
    ) {
        self.bringForward = bringForward
        self.observeEvidence = observeEvidence
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
            stopObservingIfIdle()
        case .active:
            startObserving()
            if runtime.demandGeneration != previousGeneration {
                evaluateFrontmostApplication()
            }
        }
    }

    public func stayFocused() {
        guard let work = runtime.currentWork else { return }
        var next = runtime
        next.stayFocused()
        runtime = next

        guard resumptionTreatmentEnabled else {
            observeEvidence(.stayFocusedResumptionTreatmentDisabled)
            return
        }
        guard let identity = work.resumptionProcessIdentity else {
            observeEvidence(.stayFocusedResumptionIneligible)
            return
        }
        guard let application = resolveApplication(identity) else {
            observeEvidence(.stayFocusedResumptionIneligible)
            return
        }
        guard application.focusGuardProcessIdentity == identity else {
            resumptionTreatmentEnabled = false
            observeEvidence(.stayFocusedResumptionResolutionMismatch)
            return
        }

        let attempt = PendingResumption(id: UUID(), processIdentity: identity)
        pendingResumption = attempt
        guard application.focusGuardActivate() else {
            pendingResumption = nil
            observeEvidence(.stayFocusedResumptionRejected)
            stopObservingIfIdle()
            return
        }

        scheduleResumptionTimeout(for: attempt)
        observeEvidence(.stayFocusedResumptionAttemptAccepted)
    }

    public func openOnce() {
        guard let work = runtime.currentWork else { return }
        guard exactApplication(for: work.processIdentity) != nil else {
            failOpen(work, recording: .openOnceNotAccepted)
            return
        }

        var next = runtime
        next.allowOnce()
        runtime = next

        guard let app = exactApplication(for: work.processIdentity) else {
            failOpenAllowedProcess(
                work.processIdentity,
                recording: .openOnceNotAccepted
            )
            return
        }
        _ = app.focusGuardUnhide()
        guard let app = exactApplication(for: work.processIdentity),
            app.focusGuardActivate()
        else {
            failOpenAllowedProcess(
                work.processIdentity,
                recording: .openOnceNotAccepted
            )
            return
        }
        runtime.degraded = false
        observeEvidence(.openOnceActivationAccepted)
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

    func handleActivation(
        processIdentity: FocusGuardProcessIdentity,
        displayName: String,
        isSelf: Bool
    ) {
        let selfID = ownBundleIDs.contains(processIdentity.bundleIdentifier)
        resolvePendingResumption(
            activatedProcessIdentity: processIdentity,
            isSelf: isSelf || selfID
        )
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
        guard let app = exactApplication(for: work.processIdentity) else {
            failOpen(work)
            return
        }
        _ = app.focusGuardHide()

        guard runtime.isCurrent(work) else { return }
        guard let app = exactApplication(for: work.processIdentity) else {
            failOpen(work)
            return
        }
        if app.focusGuardIsHidden {
            runtime.degraded = false
            bringForward()
            observeEvidence(.promptOfferedAfterConfirmedHide)
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

    private func failOpen(
        _ work: FocusGuardWork,
        recording event: FocusGuardEvidenceEvent = .interceptionFailedBeforePrompt
    ) {
        guard runtime.isCurrent(work) else { return }
        var next = runtime
        next.degraded = true
        next.interception = nil
        runtime = next
        observeEvidence(event)
    }

    private func failOpenAllowedProcess(
        _ identity: FocusGuardProcessIdentity,
        recording event: FocusGuardEvidenceEvent
    ) {
        guard runtime.allowedProcessIdentity == identity else { return }
        var next = runtime
        next.allowedProcessIdentity = nil
        next.degraded = true
        runtime = next
        observeEvidence(event)
    }

    private func handleDeactivation(processIdentity: FocusGuardProcessIdentity) {
        var next = runtime
        next.deactivated(processIdentity: processIdentity)
        runtime = next
    }

    private func exactApplication(
        for identity: FocusGuardProcessIdentity
    ) -> (any FocusGuardApplication)? {
        guard let application = resolveApplication(identity),
            application.focusGuardProcessIdentity == identity
        else { return nil }
        return application
    }

    private func scheduleResumptionTimeout(for attempt: PendingResumption) {
        resumptionTimeoutTask?.cancel()
        resumptionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: .seconds(Self.resumptionConfirmationTimeout)
            )
            guard !Task.isCancelled else { return }
            self?.handleResumptionTimeout(attemptID: attempt.id)
        }
    }

    private func resolvePendingResumption(
        activatedProcessIdentity: FocusGuardProcessIdentity,
        isSelf: Bool
    ) {
        guard !isSelf, let pendingResumption else { return }
        self.pendingResumption = nil
        resumptionTimeoutTask?.cancel()
        resumptionTimeoutTask = nil

        if activatedProcessIdentity == pendingResumption.processIdentity {
            observeEvidence(.resumptionConfirmed)
        } else {
            resumptionTreatmentEnabled = false
            observeEvidence(.resumptionActivationMismatch)
        }
        stopObservingIfIdle()
    }

    func expirePendingResumptionForTesting() {
        guard let pendingResumption else { return }
        handleResumptionTimeout(attemptID: pendingResumption.id)
    }

    private func handleResumptionTimeout(attemptID: UUID) {
        guard pendingResumption?.id == attemptID else { return }
        pendingResumption = nil
        resumptionTimeoutTask?.cancel()
        resumptionTimeoutTask = nil
        observeEvidence(.resumptionTimedOut)
        stopObservingIfIdle()
    }

    private func stopObservingIfIdle() {
        guard case .inactive = runtime.demand, pendingResumption == nil else { return }
        stopObserving()
    }
}
