import Foundation

/// The Live Session facts a user-facing adapter displayed before issuing an
/// action. Matching happens while `world.lock` is held.
public struct ObservedLiveBeat: Equatable, Sendable {
    public let sessionID: UUID
    public let beat: SessionPhase
    public let isRecoveryPaused: Bool

    public init(
        sessionID: UUID,
        beat: SessionPhase,
        isRecoveryPaused: Bool
    ) {
        self.sessionID = sessionID
        self.beat = beat
        self.isRecoveryPaused = isRecoveryPaused
    }

    public init(_ live: SessionSnapshot) {
        self.init(
            sessionID: live.id,
            beat: live.phase,
            isRecoveryPaused: live.isPaused
        )
    }

    fileprivate func matches(_ live: SessionSnapshot?) -> Bool {
        guard let live else { return false }
        return live.id == sessionID
            && live.phase == beat
            && live.isPaused == isRecoveryPaused
    }
}

/// A related persistence step failed after World itself became durable. The
/// caller must adopt the committed World before presenting the issue.
public enum WorldCommitWarning: Equatable, Sendable {
    case auxiliaryPersistenceFailed
}

/// Durable action output. Transition facts describe the World loaded and
/// committed under the same `world.lock` lease.
public struct WorldCommit: Equatable, Sendable {
    public let world: World
    public let before: ObservedLiveBeat?
    public let after: ObservedLiveBeat?
    public let completedSession: CompletedSession?
    public let changed: Bool
    public let warnings: [WorldCommitWarning]

    package init(
        world: World,
        before: ObservedLiveBeat?,
        after: ObservedLiveBeat?,
        completedSession: CompletedSession?,
        changed: Bool,
        warnings: [WorldCommitWarning] = []
    ) {
        self.world = world
        self.before = before
        self.after = after
        self.completedSession = completedSession
        self.changed = changed
        self.warnings = warnings
    }

    /// The exact completed Session's explicit Next Step. It never falls back
    /// to an older Session or to the completed Intention.
    public var completedNextStep: String? {
        completedSession.flatMap(NextStepSuggestion.forSession)
    }
}

/// Stale user gestures are expected races, not persistence failures. Both
/// outcomes carry the durable World that the caller should adopt.
public enum WorldApplyResult: Equatable, Sendable {
    case committed(WorldCommit)
    case stale(current: World)

    public var world: World {
        switch self {
        case .committed(let commit):
            return commit.world
        case .stale(let current):
            return current
        }
    }

    public var commit: WorldCommit? {
        guard case .committed(let commit) = self else { return nil }
        return commit
    }
}

/// The action-first mutation seam over the existing Store transaction and
/// Engine state machine.
public struct WorldAuthority: Sendable {
    private let persistence: any WorldAuthorityPersistence

    /// Local-only persistence, used by callers that do not maintain related
    /// sync or recovery state.
    public init(store: Store) {
        self.persistence = StoreWorldAuthorityPersistence(store: store)
    }

    package init(persistence: any WorldAuthorityPersistence) {
        self.persistence = persistence
    }

    /// Apply an action to whichever World is current when `world.lock` is
    /// acquired. This is appropriate for non-visual callers such as the CLI.
    public func apply(_ event: Event, at timestamp: Date) throws -> WorldApplyResult {
        try persistence.commit(
            WorldActionRequest(event: event, observed: nil, timestamp: timestamp)
        )
    }

    /// Apply an action only if the displayed Live Session still matches while
    /// `world.lock` is held.
    public func apply(
        _ event: Event,
        observed: ObservedLiveBeat,
        at timestamp: Date
    ) throws -> WorldApplyResult {
        try persistence.commit(
            WorldActionRequest(event: event, observed: observed, timestamp: timestamp)
        )
    }
}

package struct WorldActionRequest: Sendable {
    package let event: Event
    package let observed: ObservedLiveBeat?
    package let timestamp: Date

    package init(
        event: Event,
        observed: ObservedLiveBeat?,
        timestamp: Date
    ) {
        self.event = event
        self.observed = observed
        self.timestamp = timestamp
    }
}

/// Internal seam for concrete persistence adapters. Feature callers only see
/// `WorldAuthority.apply`; they cannot supply lock-held callbacks.
package protocol WorldAuthorityPersistence: Sendable {
    func commit(_ request: WorldActionRequest) throws -> WorldApplyResult
}

package struct WorldActionFacts: Sendable {
    package let before: ObservedLiveBeat?
    package let after: ObservedLiveBeat?
    package let completedSession: CompletedSession?
    package let changed: Bool

    package func commit(
        world: World,
        warnings: [WorldCommitWarning] = []
    ) -> WorldCommit {
        WorldCommit(
            world: world,
            before: before,
            after: after,
            completedSession: completedSession,
            changed: changed,
            warnings: warnings
        )
    }
}

package enum WorldActionMutation {
    package static func apply(
        _ request: WorldActionRequest,
        to engine: inout Engine
    ) throws -> WorldActionFacts? {
        let beforeWorld = engine.world
        let before = beforeWorld.live.map(ObservedLiveBeat.init)

        if let observed = request.observed, !observed.matches(beforeWorld.live) {
            return nil
        }

        try engine.apply(request.event, now: request.timestamp)
        let afterWorld = engine.world
        let completedSession = exactCompletion(
            event: request.event,
            before: beforeWorld,
            after: afterWorld
        )
        return WorldActionFacts(
            before: before,
            after: afterWorld.live.map(ObservedLiveBeat.init),
            completedSession: completedSession,
            changed: afterWorld != beforeWorld
        )
    }

    private static func exactCompletion(
        event: Event,
        before: World,
        after: World
    ) -> CompletedSession? {
        guard case .skip = event,
            let live = before.live,
            live.phase == .closeBeat,
            after.live == nil,
            after.history.count > before.history.count
        else { return nil }
        return after.history.dropFirst(before.history.count).last(where: { $0.id == live.id })
    }
}

package struct StoreWorldAuthorityPersistence: WorldAuthorityPersistence {
    private let store: Store

    package init(store: Store) {
        self.store = store
    }

    package func commit(_ request: WorldActionRequest) throws -> WorldApplyResult {
        var facts: WorldActionFacts?
        var observationWasStale = false
        let engine = try store.update { engine in
            guard let applied = try WorldActionMutation.apply(request, to: &engine) else {
                observationWasStale = true
                return
            }
            facts = applied
        }

        if observationWasStale {
            return .stale(current: engine.world)
        }
        guard let facts else {
            preconditionFailure("World action completed without transition facts")
        }
        return .committed(facts.commit(world: engine.world))
    }
}
