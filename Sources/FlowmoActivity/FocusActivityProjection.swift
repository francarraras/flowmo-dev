import FlowmoCore
import Foundation

/// The complete public glance: an opaque session identity and its persisted clock origin.
public struct FocusActivityProjection: Equatable, Sendable {
    public let sessionID: UUID
    public let startedAt: Date

    public init?(world: World) {
        guard let live = world.live, live.phase == .focus, !live.isPaused else { return nil }
        self.sessionID = live.id
        self.startedAt = live.focusStartedAt ?? live.phaseStartedAt
    }

    public init(sessionID: UUID, startedAt: Date) {
        self.sessionID = sessionID
        self.startedAt = startedAt
    }
}
