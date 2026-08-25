import FlowmoCore
import Foundation

public enum WorldSyncRecordKind: String, Codable, Equatable, Sendable {
    case head = "FlowmoHead"
    case completedSession = "FlowmoCompletedSession"
}

public struct WorldSyncRecordPayload: Equatable, Sendable {
    public let name: String
    public let kind: WorldSyncRecordKind
    public let data: Data

    public init(name: String, kind: WorldSyncRecordKind, data: Data) {
        self.name = name
        self.kind = kind
        self.data = data
    }
}

public enum WorldSyncRecordCodec {
    public static let headRecordName = "world-head"
    public static let sessionRecordPrefix = "session-"

    public static func records(for snapshot: WorldSyncSnapshot) throws -> [WorldSyncRecordPayload] {
        var records = [
            WorldSyncRecordPayload(
                name: headRecordName,
                kind: .head,
                data: try JSONEncoder.flowmo.encode(snapshot.head)
            )
        ]
        records.append(
            contentsOf: try snapshot.history.map { session in
                WorldSyncRecordPayload(
                    name: sessionRecordName(session.id),
                    kind: .completedSession,
                    data: try JSONEncoder.flowmo.encode(session)
                )
            }
        )
        return records
    }

    public static func sessionRecordName(_ id: UUID) -> String {
        sessionRecordPrefix + id.uuidString.lowercased()
    }

    public static func sessionID(recordName: String) -> UUID? {
        guard recordName.hasPrefix(sessionRecordPrefix) else { return nil }
        return UUID(uuidString: String(recordName.dropFirst(sessionRecordPrefix.count)))
    }

    public static func decodeHead(_ data: Data) throws -> WorldSyncHead {
        let head = try JSONDecoder.flowmo.decode(WorldSyncHead.self, from: data)
        guard head.schemaVersion == WorldSyncHead.schemaVersion else {
            throw WorldSyncRecordError.unsupportedSchema(head.schemaVersion)
        }
        return head
    }

    public static func decodeSession(_ data: Data, recordName: String) throws -> CompletedSession {
        guard let expectedID = sessionID(recordName: recordName) else {
            throw WorldSyncRecordError.invalidRecordName(recordName)
        }
        let session = try JSONDecoder.flowmo.decode(CompletedSession.self, from: data)
        guard session.id == expectedID else {
            throw WorldSyncRecordError.sessionIdentityMismatch
        }
        var world = World.empty
        world.history = [session]
        try world.validateForPersistence()
        return session
    }

    public static func assemble(
        headData: Data,
        sessionDataByName: [String: Data]
    ) throws -> WorldSyncSnapshot {
        let head = try decodeHead(headData)
        var sessions: [CompletedSession] = []
        for id in head.historyIDs {
            let name = sessionRecordName(id)
            guard let data = sessionDataByName[name] else {
                throw WorldSyncRecordError.missingSession(id)
            }
            sessions.append(try decodeSession(data, recordName: name))
        }
        let snapshot = WorldSyncSnapshot(head: head, history: sessions)
        _ = try snapshot.applying(to: .empty)
        return snapshot
    }
}

public enum WorldSyncRecordError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidRecordName(String)
    case sessionIdentityMismatch
    case missingSession(UUID)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported Flowmo sync schema \(version)."
        case .invalidRecordName:
            return "Invalid Flowmo sync record name."
        case .sessionIdentityMismatch:
            return "Flowmo sync session identity does not match its record."
        case .missingSession:
            return "Flowmo sync snapshot is incomplete."
        }
    }
}
