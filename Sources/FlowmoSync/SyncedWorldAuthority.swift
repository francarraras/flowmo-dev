import FlowmoCore
import Foundation

extension WorldAuthority {
    /// Action persistence for app surfaces that also own private-sync
    /// metadata. The metadata lease is nested inside `world.lock`.
    public init(
        store: Store,
        syncMetadataStore: WorldSyncMetadataStore
    ) {
        self.init(
            persistence: SyncedWorldAuthorityPersistence(
                worldStore: store,
                metadataStore: syncMetadataStore
            )
        )
    }
}

/// Applies an Engine action to the latest locked World and, for a committed
/// action, clears remote ownership in the same `world.lock` -> `sync.lock`
/// order. World remains authoritative if related metadata cannot be acquired
/// or saved; the durable commit carries a warning for the caller to surface.
package struct SyncedWorldAuthorityPersistence: WorldAuthorityPersistence {
    private let worldStore: Store
    private let metadataStore: WorldSyncMetadataStore

    package init(
        worldStore: Store,
        metadataStore: WorldSyncMetadataStore
    ) {
        self.worldStore = worldStore
        self.metadataStore = metadataStore
    }

    package func commit(_ request: WorldActionRequest) throws -> WorldApplyResult {
        var facts: WorldActionFacts?
        var observationWasStale = false
        var metadataLease: WorldSyncMetadataLease?
        var nextMetadata: WorldSyncMetadata?
        var auxiliaryPersistenceFailed = false
        defer { metadataLease = nil }

        let engine = try worldStore.update(
            { engine in
                guard let applied = try WorldActionMutation.apply(request, to: &engine) else {
                    observationWasStale = true
                    return
                }
                facts = applied

                do {
                    let lease = try metadataStore.acquireForWorldCommit()
                    var metadata = lease.metadata
                    metadata.remoteLiveSessionID = nil
                    metadataLease = lease
                    if metadata != lease.metadata {
                        nextMetadata = metadata
                    }
                } catch {
                    auxiliaryPersistenceFailed = true
                }
            },
            afterPersist: { _ in
                defer { metadataLease = nil }
                guard let metadataLease, let nextMetadata else { return }
                do {
                    try metadataLease.save(nextMetadata)
                } catch {
                    auxiliaryPersistenceFailed = true
                }
            }
        )

        if observationWasStale {
            return .stale(current: engine.world)
        }
        guard let facts else {
            preconditionFailure("World action completed without transition facts")
        }
        let warnings: [WorldCommitWarning] =
            auxiliaryPersistenceFailed ? [.auxiliaryPersistenceFailed] : []
        return .committed(
            facts.commit(world: engine.world, warnings: warnings)
        )
    }
}
