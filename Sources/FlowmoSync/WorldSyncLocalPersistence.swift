import FlowmoCore
import Foundation

/// A prepared local sync mutation. Reconciliation receives the latest World
/// while `world.lock` is held and returns the World plus any decision the
/// CloudKit adapter needs after persistence.
package struct WorldSyncLocalMutation<Output> {
    package let world: World
    package let output: Output

    package init(world: World, output: Output) {
        self.world = world
        self.output = output
    }
}

/// The durable result of a local sync mutation.
package struct WorldSyncLocalCommit<Output> {
    package let world: World
    package let metadata: WorldSyncMetadata
    package let worldChanged: Bool
    package let output: Output

    package init(
        world: World,
        metadata: WorldSyncMetadata,
        worldChanged: Bool,
        output: Output
    ) {
        self.world = world
        self.metadata = metadata
        self.worldChanged = worldChanged
        self.output = output
    }
}

/// The local transaction seam used by Cloud sync.
///
/// `Store.update` reloads World under `world.lock`, then this seam reloads the
/// latest metadata using the shared `world.lock` -> `sync.lock` order. The
/// metadata lease remains held while World becomes durable and through the
/// matching metadata save, so another metadata writer cannot invalidate the
/// plan between those operations. This is ordered two-file persistence, not a
/// crash-atomic aggregate.
package struct WorldSyncLocalPersistence: Sendable {
    private let worldStore: Store
    private let metadataStore: WorldSyncMetadataStore

    package init(
        worldStore: Store,
        metadataStore: WorldSyncMetadataStore
    ) {
        self.worldStore = worldStore
        self.metadataStore = metadataStore
    }

    package func commit<Output>(
        _ mutate: (
            _ currentWorld: World,
            _ nextMetadata: inout WorldSyncMetadata
        ) throws -> WorldSyncLocalMutation<Output>
    ) throws -> WorldSyncLocalCommit<Output> {
        var lease: WorldSyncMetadataLease?
        defer { lease = nil }
        var nextMetadata: WorldSyncMetadata?
        var prepared: WorldSyncLocalMutation<Output>?
        var worldChanged = false

        let engine = try worldStore.update(
            { engine in
                let acquiredLease = try metadataStore.acquireForWorldCommit()
                lease = acquiredLease
                var latestMetadata = acquiredLease.metadata
                let mutation = try mutate(engine.world, &latestMetadata)
                worldChanged = mutation.world != engine.world
                engine.world = mutation.world
                nextMetadata = latestMetadata
                prepared = mutation
            },
            afterPersist: { _ in
                defer { lease = nil }
                guard let lease, let nextMetadata else {
                    preconditionFailure("Store.update persisted without preparing sync metadata")
                }
                try lease.save(nextMetadata)
            }
        )

        guard let prepared, let nextMetadata else {
            preconditionFailure("Store.update returned without running its mutation")
        }
        return WorldSyncLocalCommit(
            world: engine.world,
            metadata: nextMetadata,
            worldChanged: worldChanged,
            output: prepared.output
        )
    }
}
