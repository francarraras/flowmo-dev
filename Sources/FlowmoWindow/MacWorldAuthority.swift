import FlowmoCore
import FlowmoSync
import Foundation

package struct ObservedPrime: Equatable, Sendable {
    package let beat: ObservedLiveBeat

    package init?(_ live: SessionSnapshot?) {
        guard let live, live.phase == .prime, !live.isPaused else { return nil }
        self.beat = ObservedLiveBeat(live)
    }
}

package enum MacSyncWarning: Equatable, Sendable {
    case metadataUnavailable
}

package struct MacDurableCommit: Equatable, Sendable {
    package let action: WorldCommit
    package let syncWarning: MacSyncWarning?
}

package struct MacRecoveryFailure {
    package let operation: MacRecoveryMutation.PostPersistOperation
    package let underlyingError: any Error
}

package enum MacPrePersistStage: Equatable, Sendable {
    case loadWorld
    case applyAction
    case recoveryWriteAhead
    case persistWorld
}

package struct MacPrePersistFailure {
    package let stage: MacPrePersistStage
    package let underlyingError: any Error
}

/// The durability result for a Mac World action. Callers must adopt every
/// durable commit before presenting either its sync warning or recovery block.
package enum MacActionOutcome {
    case stale(current: World)
    case committed(MacDurableCommit)
    case committedRecoveryBlocked(MacDurableCommit, MacRecoveryFailure)
    case notCommitted(MacPrePersistFailure)

    package var world: World? {
        switch self {
        case .stale(let current):
            return current
        case .committed(let commit), .committedRecoveryBlocked(let commit, _):
            return commit.action.world
        case .notCommitted:
            return nil
        }
    }
}

/// Actor-safe Mac action module. Its concrete MainActor interface is the seam;
/// it deliberately does not conform to Core's nonisolated persistence seam.
/// Engine remains the sole Loop state machine.
@MainActor
package final class MacWorldAuthority {
    private let store: Store
    private let metadataStore: WorldSyncMetadataStore
    private let recovery: any MacRecoveryPersistence
    private let workContextHandoff: any WorkContextHandoff

    package init(
        store: Store,
        metadataStore: WorldSyncMetadataStore,
        recovery: any MacRecoveryPersistence,
        workContextHandoff: any WorkContextHandoff
    ) {
        self.store = store
        self.metadataStore = metadataStore
        self.recovery = recovery
        self.workContextHandoff = workContextHandoff
    }

    /// Apply an action to the exact Live Session facts displayed by the Mac.
    package func apply(
        _ event: Event,
        observed: ObservedLiveBeat,
        at timestamp: Date
    ) -> MacActionOutcome {
        commit(
            WorldActionRequest(
                event: event,
                observed: observed,
                timestamp: timestamp
            ),
            focusNowSessionID: nil
        )
    }

    /// Apply an action to whichever World is current under `world.lock`.
    package func applyCurrent(
        _ event: Event,
        at timestamp: Date
    ) -> MacActionOutcome {
        commit(
            WorldActionRequest(
                event: event,
                observed: nil,
                timestamp: timestamp
            ),
            focusNowSessionID: nil
        )
    }

    /// Commit only an exact, unpaused Prime -> Focus transition, then consume
    /// the eligible Work Handoff target while `world.lock` remains held.
    package func focusNow(
        _ observedPrime: ObservedPrime,
        at timestamp: Date
    ) -> MacActionOutcome {
        commit(
            WorldActionRequest(
                event: .skip,
                observed: observedPrime.beat,
                timestamp: timestamp
            ),
            focusNowSessionID: observedPrime.beat.sessionID
        )
    }

    private func commit(
        _ request: WorldActionRequest,
        focusNowSessionID: UUID?
    ) -> MacActionOutcome {
        var facts: WorldActionFacts?
        var staleCurrent: World?
        var metadataLease: WorldSyncMetadataLease?
        var nextMetadata: WorldSyncMetadata?
        var syncWarning: MacSyncWarning?
        var postPersistRecovery: MacRecoveryMutation?
        var recoveryFailure: MacRecoveryFailure?
        var failureStage = MacPrePersistStage.loadWorld
        defer { metadataLease = nil }

        do {
            let engine = try store.update(
                { engine in
                    failureStage = .applyAction
                    let lockedBeforeLive = engine.world.live
                    guard let applied = try WorldActionMutation.apply(request, to: &engine) else {
                        staleCurrent = engine.world
                        return
                    }
                    facts = applied

                    var requiresPostPersistAdoption = false
                    do {
                        let lease = try metadataStore.acquireForWorldCommit()
                        var metadata = lease.metadata
                        requiresPostPersistAdoption = metadata.identifiesRemoteLiveSession(
                            lockedBeforeLive
                        )
                        metadata.remoteLiveSessionID = nil
                        metadataLease = lease
                        if metadata != lease.metadata {
                            nextMetadata = metadata
                        }
                    } catch {
                        syncWarning = .metadataUnavailable
                    }

                    if let live = engine.world.live {
                        if requiresPostPersistAdoption {
                            postPersistRecovery = .adoptLiveAfterWorldPersistence(
                                sessionID: live.id,
                                observedAt: request.timestamp
                            )
                        } else {
                            failureStage = .recoveryWriteAhead
                            try recovery.persist(
                                .writeAheadLive(
                                    sessionID: live.id,
                                    observedAt: request.timestamp
                                )
                            )
                        }
                    } else {
                        postPersistRecovery = .clearAfterWorldPersistence(
                            observedAt: request.timestamp
                        )
                    }
                    failureStage = .persistWorld
                },
                afterPersist: { engine in
                    guard staleCurrent == nil else { return }
                    defer { metadataLease = nil }

                    if let metadataLease, let nextMetadata {
                        do {
                            try metadataLease.save(nextMetadata)
                        } catch {
                            syncWarning = .metadataUnavailable
                        }
                    }

                    if let postPersistRecovery {
                        do {
                            try self.recovery.persist(postPersistRecovery)
                        } catch {
                            guard let operation = postPersistRecovery.postPersistOperation else {
                                preconditionFailure("Write-ahead recovery cannot run after World persistence")
                            }
                            recoveryFailure = MacRecoveryFailure(
                                operation: operation,
                                underlyingError: error
                            )
                            return
                        }
                    }

                    guard let focusNowSessionID,
                        let live = engine.world.live,
                        live.id == focusNowSessionID,
                        live.phase == .focus,
                        !live.isPaused
                    else { return }
                    let excluded: Set<String>
                    if case .active(_, let bundleIdentifiers) = FocusGuard.demand(world: engine.world) {
                        excluded = bundleIdentifiers
                    } else {
                        excluded = []
                    }
                    self.workContextHandoff.activateBoundTarget(
                        for: focusNowSessionID,
                        excludingBundleIdentifiers: excluded
                    )
                    self.workContextHandoff.retainOnly(sessionID: nil)
                }
            )

            if let staleCurrent {
                return .stale(current: staleCurrent)
            }
            guard let facts else {
                preconditionFailure("Mac World action completed without transition facts")
            }
            let durable = MacDurableCommit(
                action: facts.commit(world: engine.world),
                syncWarning: syncWarning
            )
            if let recoveryFailure {
                return .committedRecoveryBlocked(durable, recoveryFailure)
            }
            return .committed(durable)
        } catch {
            return .notCommitted(
                MacPrePersistFailure(
                    stage: failureStage,
                    underlyingError: error
                )
            )
        }
    }

}
