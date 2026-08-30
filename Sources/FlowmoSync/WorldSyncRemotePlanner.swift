import FlowmoCore
import Foundation

package enum WorldSyncRemoteProcessing: Equatable {
    case deletionAccountUnavailable
    case deletionPending
    case conflict(WorldSyncConflict)
    case merged(snapshot: WorldSyncSnapshot, remote: WorldSyncSnapshot?)
}

package enum WorldSyncConflictCommit: Equatable {
    case staleWorld
    case staleConflict
    case staleRemote
    case resolved(snapshot: WorldSyncSnapshot, shouldStage: Bool)
}

/// Pure reconciliation planning for remote facts already persisted in sync
/// metadata. The caller supplies the latest World from the local transaction.
package enum WorldSyncRemotePlanner {
    /// Resolves only the exact conflict the person acted on. Every comparison
    /// happens against the latest World and metadata loaded by the surrounding
    /// ordered local transaction.
    package static func resolveDisplayedConflict(
        _ conflict: WorldSyncConflict,
        choosing choice: WorldSyncChoice,
        currentWorld: World,
        metadata: inout WorldSyncMetadata
    ) throws -> WorldSyncLocalMutation<WorldSyncConflictCommit> {
        guard metadata.conflict == conflict else {
            return WorldSyncLocalMutation(
                world: currentWorld,
                output: .staleConflict
            )
        }
        guard try remoteFactsMatch(conflict, metadata: metadata) else {
            return WorldSyncLocalMutation(
                world: currentWorld,
                output: .staleRemote
            )
        }
        let current = WorldSyncSnapshot(
            world: currentWorld,
            generation: conflict.local.head.generation
        )
        guard current == conflict.local else {
            return WorldSyncLocalMutation(
                world: currentWorld,
                output: .staleWorld
            )
        }

        let cloudHeadExists = try metadata.remoteSnapshot != nil
        let resolved = WorldSyncReconciler.resolve(conflict, choosing: choice)
        let cloudSide = conflict.remote
        let shouldStage = choice == .local || resolved != cloudSide || !cloudHeadExists

        metadata.conflict = nil
        metadata.accountChangeRequiresChoice = false
        metadata.generation = resolved.head.generation
        metadata.remoteLiveSessionID = choice == .remote ? resolved.head.live?.id : nil
        metadata.base = cloudSide
        if !shouldStage {
            metadata.base = resolved
            metadata.pending = nil
            metadata.pendingRevisions = [:]
        }

        return WorldSyncLocalMutation(
            world: try resolved.applying(to: currentWorld),
            output: .resolved(
                snapshot: resolved,
                shouldStage: shouldStage
            )
        )
    }

    /// A visible conflict can outlive a background fetch. A choice is valid
    /// only while the latest remote facts still describe the remote side the
    /// person saw. Account/reset conflicts may intentionally synthesize an
    /// empty remote side when the cloud head is absent.
    package static func remoteFactsMatch(
        _ conflict: WorldSyncConflict,
        metadata: WorldSyncMetadata
    ) throws -> Bool {
        if let remote = try metadata.remoteSnapshot {
            return remote == conflict.remote
        }
        switch conflict.kind {
        case .account, .resetGeneration:
            return conflict.remote.isEffectivelyEmpty
        case .initialImport, .liveSession, .profile, .completedSession:
            return false
        }
    }

    package static func process(
        currentWorld: World,
        metadata: inout WorldSyncMetadata,
        reconcileExistingConflict: Bool
    ) throws -> WorldSyncLocalMutation<WorldSyncRemoteProcessing> {
        let local = WorldSyncSnapshot(
            world: currentWorld,
            generation: metadata.generation
        )

        if metadata.cloudDeletionPending, !metadata.canSendCloudDeletion {
            metadata.pending = local
            metadata.remoteHeadData = nil
            metadata.remoteSessionData = [:]
            metadata.recordSystemFields = [:]
            metadata.pendingRevisions = [:]
            metadata.pendingDeletionRecordNames = []
            return WorldSyncLocalMutation(
                world: currentWorld,
                output: .deletionAccountUnavailable
            )
        }

        if metadata.cloudDeletionPending {
            metadata.pending = local
            metadata.base = nil
            metadata.conflict = nil
            metadata.remoteLiveSessionID = nil
            metadata.forgetOrphanedRemoteSessions(referencedBy: nil)
            metadata.remoteHeadData = nil
            return WorldSyncLocalMutation(
                world: currentWorld,
                output: .deletionPending
            )
        }

        if let conflict = metadata.conflict, !reconcileExistingConflict {
            return WorldSyncLocalMutation(
                world: currentWorld,
                output: .conflict(conflict)
            )
        }

        let remote = try metadata.remoteSnapshot
        metadata.forgetOrphanedRemoteSessions(referencedBy: remote)
        let outcome: WorldSyncReconciliation
        if metadata.accountChangeRequiresChoice {
            let cloud = remote ?? WorldSyncSnapshot(world: .empty, generation: UUID())
            outcome = .conflict(
                WorldSyncConflict(kind: .account, local: local, remote: cloud, ancestor: nil)
            )
        } else if let base = metadata.base {
            if let remote {
                outcome = WorldSyncReconciler.reconcile(
                    local: local,
                    remote: remote,
                    ancestor: base
                )
            } else {
                let deleted = WorldSyncSnapshot(world: .empty, generation: UUID())
                outcome = .conflict(
                    WorldSyncConflict(
                        kind: .resetGeneration,
                        local: local,
                        remote: deleted,
                        ancestor: base
                    )
                )
            }
        } else {
            outcome = WorldSyncReconciler.bootstrap(local: local, remote: remote)
        }

        switch outcome {
        case .conflict(let conflict):
            metadata.conflict = conflict
            metadata.pending = nil
            metadata.pendingRevisions = [:]
            return WorldSyncLocalMutation(
                world: currentWorld,
                output: .conflict(conflict)
            )
        case .merged(let merged):
            let remoteChangedLive = merged.head.live != local.head.live
            metadata.conflict = nil
            metadata.generation = merged.head.generation
            metadata.base = remote ?? merged
            metadata.remoteLiveSessionID =
                remoteChangedLive ? merged.head.live?.id : metadata.remoteLiveSessionID
            if merged == remote {
                metadata.pending = nil
                metadata.pendingRevisions = [:]
            }
            return WorldSyncLocalMutation(
                world: try merged.applying(to: currentWorld),
                output: .merged(snapshot: merged, remote: remote)
            )
        }
    }
}
