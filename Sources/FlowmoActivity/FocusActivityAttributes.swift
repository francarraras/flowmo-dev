#if os(iOS)
    import ActivityKit
    import Foundation

    public struct FocusActivityAttributes: ActivityAttributes, Sendable {
        public struct ContentState: Codable, Hashable, Sendable {
            public var startedAt: Date

            public init(startedAt: Date) {
                self.startedAt = startedAt
            }
        }

        public let sessionID: UUID

        public init(sessionID: UUID) {
            self.sessionID = sessionID
        }
    }
#endif
