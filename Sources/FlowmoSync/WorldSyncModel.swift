import FlowmoCore
import Foundation

/// The cross-device portion of `World`. Focus Guard and cue preferences remain
/// device-local; the live loop, fixed break ratio, resumption intention, and
/// completed sessions are shared.
public struct WorldSyncHead: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var generation: UUID
    public var live: SessionSnapshot?
    public var breakRatio: Double
    public var lastIntention: String

    public init(
        generation: UUID,
        live: SessionSnapshot?,
        breakRatio: Double,
        lastIntention: String,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.live = live
        self.breakRatio = breakRatio
        self.lastIntention = lastIntention
    }
}

public struct WorldSyncSnapshot: Codable, Equatable, Sendable {
    public var head: WorldSyncHead
    public var history: [CompletedSession]

    public init(head: WorldSyncHead, history: [CompletedSession]) {
        self.head = head
        self.history = Self.canonicalHistory(history)
    }

    public init(world: World, generation: UUID) {
        self.init(
            head: WorldSyncHead(
                generation: generation,
                live: world.live,
                breakRatio: world.profile.breakRatio,
                lastIntention: world.profile.lastIntention
            ),
            history: world.history
        )
    }

    public var isEffectivelyEmpty: Bool {
        head.live == nil
            && history.isEmpty
            && head.lastIntention.isEmpty
            && head.breakRatio == Config.default.defaultBreakRatio
    }

    /// Apply shared state while retaining settings and legacy compatibility
    /// fields that belong to this device's local store.
    public func applying(to local: World) throws -> World {
        var merged = local
        merged.live = head.live
        merged.history = Self.oldestFirst(history)
        merged.profile.breakRatio = head.breakRatio
        merged.profile.sessionCount = 0
        merged.profile.totalFocusSeconds = 0
        merged.profile.lastNote = nil
        merged.profile.lastIntention = head.lastIntention
        for session in merged.history {
            merged.profile = ProfileRecorder.apply(
                merged.profile,
                focusSeconds: session.focusSeconds
            )
        }
        try merged.validateForPersistence()
        return merged
    }

    static func canonicalHistory(_ history: [CompletedSession]) -> [CompletedSession] {
        history.sorted { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func oldestFirst(_ history: [CompletedSession]) -> [CompletedSession] {
        history.sorted { lhs, rhs in
            if lhs.endedAt != rhs.endedAt {
                return lhs.endedAt < rhs.endedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

public enum WorldSyncConflictKind: String, Codable, Equatable, Sendable {
    case initialImport
    case resetGeneration
    case liveSession
    case profile
    case completedSession
}

public struct WorldSyncConflict: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: WorldSyncConflictKind
    public let local: WorldSyncSnapshot
    public let remote: WorldSyncSnapshot
    public let ancestor: WorldSyncSnapshot?

    public init(
        id: UUID = UUID(),
        kind: WorldSyncConflictKind,
        local: WorldSyncSnapshot,
        remote: WorldSyncSnapshot,
        ancestor: WorldSyncSnapshot?
    ) {
        self.id = id
        self.kind = kind
        self.local = local
        self.remote = remote
        self.ancestor = ancestor
    }
}

public enum WorldSyncChoice: String, Codable, Equatable, Sendable {
    case local
    case remote
}

public enum WorldSyncReconciliation: Equatable, Sendable {
    case merged(WorldSyncSnapshot)
    case conflict(WorldSyncConflict)
}

public enum WorldSyncReconciler {
    /// First contact with an existing cloud replica is intentionally strict.
    /// An empty local store may adopt cloud state, but two independent stores
    /// never overwrite each other without a visible choice.
    public static func bootstrap(
        local: WorldSyncSnapshot,
        remote: WorldSyncSnapshot?
    ) -> WorldSyncReconciliation {
        guard let remote else { return .merged(local) }
        if local == remote || local.isEffectivelyEmpty {
            return .merged(remote)
        }
        return .conflict(
            WorldSyncConflict(
                kind: .initialImport,
                local: local,
                remote: remote,
                ancestor: nil
            )
        )
    }

    /// Three-way reconciliation against the last cloud snapshot this device
    /// applied. Independent completed sessions union safely; ambiguous changes
    /// stay unresolved until the person chooses a side.
    public static func reconcile(
        local: WorldSyncSnapshot,
        remote: WorldSyncSnapshot,
        ancestor: WorldSyncSnapshot
    ) -> WorldSyncReconciliation {
        guard local.head.generation == remote.head.generation else {
            if local.head.generation == ancestor.head.generation {
                return .merged(remote)
            }
            if remote.head.generation == ancestor.head.generation {
                return .merged(local)
            }
            return conflict(.resetGeneration, local: local, remote: remote, ancestor: ancestor)
        }

        let live: SessionSnapshot?
        switch threeWay(local.head.live, remote.head.live, ancestor.head.live) {
        case .value(let value): live = value
        case .conflict:
            return conflict(.liveSession, local: local, remote: remote, ancestor: ancestor)
        }

        let ratio: Double
        let lastIntention: String
        switch threeWay(local.head.breakRatio, remote.head.breakRatio, ancestor.head.breakRatio) {
        case .value(let value): ratio = value
        case .conflict:
            return conflict(.profile, local: local, remote: remote, ancestor: ancestor)
        }
        switch threeWay(local.head.lastIntention, remote.head.lastIntention, ancestor.head.lastIntention) {
        case .value(let value): lastIntention = value
        case .conflict:
            return conflict(.profile, local: local, remote: remote, ancestor: ancestor)
        }

        let history: [CompletedSession]
        switch mergeHistory(local: local.history, remote: remote.history, ancestor: ancestor.history) {
        case .value(let value): history = value
        case .conflict:
            return conflict(.completedSession, local: local, remote: remote, ancestor: ancestor)
        }

        return .merged(
            WorldSyncSnapshot(
                head: WorldSyncHead(
                    generation: local.head.generation,
                    live: live,
                    breakRatio: ratio,
                    lastIntention: lastIntention
                ),
                history: history
            )
        )
    }

    /// A choice selects the contested head. Completed sessions from the other
    /// side are still retained when their IDs do not collide. A reset-generation
    /// choice is wholesale so deleted data cannot be resurrected.
    public static func resolve(
        _ conflict: WorldSyncConflict,
        choosing choice: WorldSyncChoice
    ) -> WorldSyncSnapshot {
        let preferred = choice == .local ? conflict.local : conflict.remote
        let other = choice == .local ? conflict.remote : conflict.local
        guard conflict.kind != .resetGeneration else { return preferred }

        var byID = Dictionary(uniqueKeysWithValues: preferred.history.map { ($0.id, $0) })
        for session in other.history where byID[session.id] == nil {
            byID[session.id] = session
        }
        return WorldSyncSnapshot(head: preferred.head, history: Array(byID.values))
    }

    private enum Merge<Value> {
        case value(Value)
        case conflict
    }

    private static func threeWay<Value: Equatable>(
        _ local: Value,
        _ remote: Value,
        _ ancestor: Value
    ) -> Merge<Value> {
        if local == remote { return .value(local) }
        if local == ancestor { return .value(remote) }
        if remote == ancestor { return .value(local) }
        return .conflict
    }

    private static func mergeHistory(
        local: [CompletedSession],
        remote: [CompletedSession],
        ancestor: [CompletedSession]
    ) -> Merge<[CompletedSession]> {
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let ancestorByID = Dictionary(uniqueKeysWithValues: ancestor.map { ($0.id, $0) })
        let ids = Set(localByID.keys).union(remoteByID.keys).union(ancestorByID.keys)
        var merged: [CompletedSession] = []
        for id in ids {
            switch threeWay(localByID[id], remoteByID[id], ancestorByID[id]) {
            case .value(let session):
                if let session { merged.append(session) }
            case .conflict:
                return .conflict
            }
        }
        return .value(WorldSyncSnapshot.canonicalHistory(merged))
    }

    private static func conflict(
        _ kind: WorldSyncConflictKind,
        local: WorldSyncSnapshot,
        remote: WorldSyncSnapshot,
        ancestor: WorldSyncSnapshot
    ) -> WorldSyncReconciliation {
        .conflict(
            WorldSyncConflict(
                kind: kind,
                local: local,
                remote: remote,
                ancestor: ancestor
            )
        )
    }
}
