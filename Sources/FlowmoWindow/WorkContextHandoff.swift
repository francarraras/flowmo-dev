import AppKit
import Foundation

/// A private, memory-only handoff back to the app that was active before Flowmo.
/// The target is bound to one live session and is never persisted or logged.
@MainActor
public protocol WorkContextHandoff {
    func bindCandidate(to sessionID: UUID)
    func activateBoundTarget(
        for sessionID: UUID,
        excludingBundleIdentifiers: Set<String>
    )
    func transferBoundTarget(from oldSessionID: UUID, to newSessionID: UUID)
    func retainOnly(sessionID: UUID?)
}

/// Session ownership for a handoff target, kept separate from AppKit so its
/// stale-target rules remain deterministic and directly testable.
struct WorkContextHandoffState<Target> {
    private(set) var candidate: Target?
    private var boundTarget: (sessionID: UUID, target: Target)?

    mutating func observe(_ target: Target) {
        candidate = target
    }

    mutating func bindCandidate(to sessionID: UUID) {
        boundTarget = candidate.map { (sessionID, $0) }
    }

    func target(for sessionID: UUID) -> Target? {
        guard boundTarget?.sessionID == sessionID else { return nil }
        return boundTarget?.target
    }

    mutating func transfer(from oldSessionID: UUID, to newSessionID: UUID) {
        guard let target = target(for: oldSessionID) else { return }
        boundTarget = (newSessionID, target)
    }

    mutating func retainOnly(sessionID: UUID?) {
        guard boundTarget?.sessionID != sessionID else { return }
        boundTarget = nil
    }
}

/// Tracks only the latest regular non-Flowmo app and cooperatively restores it.
/// AppKit decides whether an activation request is appropriate; Flowmo fails open.
@MainActor
public final class WorkspaceWorkContextHandoff: NSObject, WorkContextHandoff {
    private let workspace: NSWorkspace
    private let currentProcessIdentifier: pid_t
    private var state = WorkContextHandoffState<NSRunningApplication>()

    public init(
        workspace: NSWorkspace = .shared,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.workspace = workspace
        self.currentProcessIdentifier = currentProcessIdentifier
        super.init()

        if let frontmost = workspace.frontmostApplication {
            observeCandidate(frontmost)
        }
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: workspace
        )
    }

    public func bindCandidate(to sessionID: UUID) {
        guard let candidate = state.candidate, isEligible(candidate) else {
            state.retainOnly(sessionID: nil)
            return
        }
        state.bindCandidate(to: sessionID)
    }

    public func activateBoundTarget(
        for sessionID: UUID,
        excludingBundleIdentifiers: Set<String>
    ) {
        guard let target = state.target(for: sessionID),
            isEligible(target),
            target.bundleIdentifier.map({ !excludingBundleIdentifiers.contains($0) }) ?? true,
            let app = NSApp
        else {
            return
        }

        app.yieldActivation(to: target)
        target.activate()
    }

    public func transferBoundTarget(from oldSessionID: UUID, to newSessionID: UUID) {
        state.transfer(from: oldSessionID, to: newSessionID)
    }

    public func retainOnly(sessionID: UUID?) {
        state.retainOnly(sessionID: sessionID)
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else { return }
        observeCandidate(application)
    }

    private func observeCandidate(_ application: NSRunningApplication) {
        guard isEligible(application) else { return }
        state.observe(application)
    }

    private func isEligible(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != currentProcessIdentifier
            && application.activationPolicy == .regular
            && !application.isTerminated
    }
}
