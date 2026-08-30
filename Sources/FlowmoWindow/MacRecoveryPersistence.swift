import Foundation

/// The recovery-marker mutations whose ordering is part of a Mac World
/// commit. The production and recording adapters are both synchronous and
/// safe to call while `world.lock` is held.
package enum MacRecoveryMutation: Equatable, Sendable {
    case writeAheadLive(sessionID: UUID, observedAt: Date)
    case adoptLiveAfterWorldPersistence(sessionID: UUID, observedAt: Date)
    case clearAfterWorldPersistence(observedAt: Date)

    package enum PostPersistOperation: Equatable, Sendable {
        case adoptLiveSession
        case clearTerminalMarker
    }

    package var postPersistOperation: PostPersistOperation? {
        switch self {
        case .writeAheadLive:
            return nil
        case .adoptLiveAfterWorldPersistence:
            return .adoptLiveSession
        case .clearAfterWorldPersistence:
            return .clearTerminalMarker
        }
    }
}

/// Local-substitutable recovery persistence. `MacProcessRecoveryMarker` is the
/// production adapter; authority tests use a recording adapter at this seam.
package protocol MacRecoveryPersistence: Sendable {
    func persist(_ mutation: MacRecoveryMutation) throws
}
