import Darwin
import FlowmoCore
import Foundation

public struct WorldSyncMetadata: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var generation: UUID
    public var accountRecordName: String?
    public var remoteLiveSessionID: UUID?
    public var accountChangeRequiresChoice: Bool
    public var cloudDeletionPending: Bool
    public var cloudDeletionAccountRecordName: String?
    public var engineState: Data?
    public var base: WorldSyncSnapshot?
    public var pending: WorldSyncSnapshot?
    public var conflict: WorldSyncConflict?
    public var remoteHeadData: Data?
    public var remoteSessionData: [String: Data]
    public var recordSystemFields: [String: Data]
    public var pendingRevisions: [String: UUID]
    public var pendingDeletionRecordNames: [String]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        generation: UUID = UUID(),
        accountRecordName: String? = nil,
        remoteLiveSessionID: UUID? = nil,
        accountChangeRequiresChoice: Bool = false,
        cloudDeletionPending: Bool = false,
        cloudDeletionAccountRecordName: String? = nil,
        engineState: Data? = nil,
        base: WorldSyncSnapshot? = nil,
        pending: WorldSyncSnapshot? = nil,
        conflict: WorldSyncConflict? = nil,
        remoteHeadData: Data? = nil,
        remoteSessionData: [String: Data] = [:],
        recordSystemFields: [String: Data] = [:],
        pendingRevisions: [String: UUID] = [:],
        pendingDeletionRecordNames: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.accountRecordName = accountRecordName
        self.remoteLiveSessionID = remoteLiveSessionID
        self.accountChangeRequiresChoice = accountChangeRequiresChoice
        self.cloudDeletionPending = cloudDeletionPending
        self.cloudDeletionAccountRecordName = cloudDeletionAccountRecordName
        self.engineState = engineState
        self.base = base
        self.pending = pending
        self.conflict = conflict
        self.remoteHeadData = remoteHeadData
        self.remoteSessionData = remoteSessionData
        self.recordSystemFields = recordSystemFields
        self.pendingRevisions = pendingRevisions
        self.pendingDeletionRecordNames = pendingDeletionRecordNames
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        generation = try values.decode(UUID.self, forKey: .generation)
        accountRecordName = try values.decodeIfPresent(String.self, forKey: .accountRecordName)
        remoteLiveSessionID = try values.decodeIfPresent(UUID.self, forKey: .remoteLiveSessionID)
        accountChangeRequiresChoice = try values.decode(Bool.self, forKey: .accountChangeRequiresChoice)
        cloudDeletionPending = try values.decodeIfPresent(Bool.self, forKey: .cloudDeletionPending) ?? false
        cloudDeletionAccountRecordName = try values.decodeIfPresent(
            String.self,
            forKey: .cloudDeletionAccountRecordName
        )
        engineState = try values.decodeIfPresent(Data.self, forKey: .engineState)
        base = try values.decodeIfPresent(WorldSyncSnapshot.self, forKey: .base)
        pending = try values.decodeIfPresent(WorldSyncSnapshot.self, forKey: .pending)
        conflict = try values.decodeIfPresent(WorldSyncConflict.self, forKey: .conflict)
        remoteHeadData = try values.decodeIfPresent(Data.self, forKey: .remoteHeadData)
        remoteSessionData = try values.decode([String: Data].self, forKey: .remoteSessionData)
        recordSystemFields = try values.decode([String: Data].self, forKey: .recordSystemFields)
        pendingRevisions = try values.decode([String: UUID].self, forKey: .pendingRevisions)
        pendingDeletionRecordNames =
            try values.decodeIfPresent([String].self, forKey: .pendingDeletionRecordNames) ?? []
    }

    public var remoteSnapshot: WorldSyncSnapshot? {
        get throws {
            guard let remoteHeadData else { return nil }
            return try WorldSyncRecordCodec.assemble(
                headData: remoteHeadData,
                sessionDataByName: remoteSessionData
            )
        }
    }

    public mutating func replaceRemote(with snapshot: WorldSyncSnapshot?) throws {
        guard let snapshot else {
            remoteHeadData = nil
            remoteSessionData = [:]
            return
        }
        let records = try WorldSyncRecordCodec.records(for: snapshot)
        remoteHeadData = records.first { $0.kind == .head }?.data
        remoteSessionData = Dictionary(
            uniqueKeysWithValues:
                records
                .filter { $0.kind == .completedSession }
                .map { ($0.name, $0.data) }
        )
    }

    public var containsPrivateCloudData: Bool {
        cloudDeletionPending
            || base?.isEffectivelyEmpty == false
            || pending?.isEffectivelyEmpty == false
            || conflict != nil
            || remoteHeadData != nil
            || !remoteSessionData.isEmpty
            || !pendingDeletionRecordNames.isEmpty
    }

    var canSendCloudDeletion: Bool {
        guard cloudDeletionPending else { return true }
        guard let deletionAccount = cloudDeletionAccountRecordName else { return true }
        return deletionAccount == accountRecordName
    }

    mutating func prepareForAccountSwitch(to account: String) {
        let deletionPending = cloudDeletionPending
        let deletionAccount = cloudDeletionAccountRecordName
        accountRecordName = account
        accountChangeRequiresChoice = !deletionPending
        cloudDeletionPending = deletionPending
        cloudDeletionAccountRecordName = deletionAccount
        engineState = nil
        base = nil
        pending =
            deletionPending
            ? WorldSyncSnapshot(world: .empty, generation: generation)
            : nil
        conflict = nil
        remoteHeadData = nil
        remoteSessionData = [:]
        recordSystemFields = [:]
        pendingRevisions = [:]
        pendingDeletionRecordNames = []
        remoteLiveSessionID = nil
    }

    /// Forget local private replicas immediately while retaining only opaque
    /// record identifiers and change tags needed to remove their cloud copies.
    @discardableResult
    public mutating func prepareDataDeletion() -> WorldSyncSnapshot {
        let deletionAccount =
            cloudDeletionPending
            ? cloudDeletionAccountRecordName
            : accountRecordName
        var names = Set(pendingDeletionRecordNames)
        names.formUnion(recordSystemFields.keys)
        names.formUnion(remoteSessionData.keys)
        for snapshot in [base, pending, conflict?.local, conflict?.remote, conflict?.ancestor].compactMap({ $0 }) {
            names.formUnion(snapshot.history.map { WorldSyncRecordCodec.sessionRecordName($0.id) })
        }
        names.remove(WorldSyncRecordCodec.headRecordName)

        let empty = WorldSyncSnapshot(world: .empty, generation: UUID())
        generation = empty.head.generation
        remoteLiveSessionID = nil
        accountChangeRequiresChoice = false
        cloudDeletionPending = true
        cloudDeletionAccountRecordName = deletionAccount
        base = nil
        pending = empty
        conflict = nil
        remoteHeadData = nil
        remoteSessionData = [:]
        pendingRevisions = [:]
        pendingDeletionRecordNames = names.sorted()
        return empty
    }

    @discardableResult
    mutating func forgetOrphanedRemoteSessions(
        referencedBy snapshot: WorldSyncSnapshot?
    ) -> [String] {
        let referenced = Set(
            (snapshot?.history ?? []).map { WorldSyncRecordCodec.sessionRecordName($0.id) }
        )
        let orphaned = Set(remoteSessionData.keys).subtracting(referenced)
        guard !orphaned.isEmpty else { return [] }
        for name in orphaned {
            remoteSessionData.removeValue(forKey: name)
        }
        pendingDeletionRecordNames = Set(pendingDeletionRecordNames).union(orphaned).sorted()
        return orphaned.sorted()
    }
}

public struct WorldSyncMetadataStore: Sendable {
    public static let maximumStateBytes: Int64 = 64 * 1024 * 1024
    public static let maximumAssetBytes: Int64 = WorldPersistenceLimits.maximumFileBytes

    public let root: URL

    public init(root: URL) {
        self.root = root.appendingPathComponent("sync", isDirectory: true)
    }

    public var stateURL: URL { root.appendingPathComponent("state.json") }

    private var lockURL: URL { root.appendingPathComponent("sync.lock") }

    public func load() throws -> WorldSyncMetadata {
        try withLock { try loadUnlocked() }
    }

    public func isRemoteLiveSession(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return (try? load().remoteLiveSessionID) == id
    }

    public func markLocalControl() throws {
        try update { metadata in
            metadata.remoteLiveSessionID = nil
        }
    }

    public func save(_ metadata: WorldSyncMetadata) throws {
        try withLock { try saveUnlocked(metadata) }
    }

    @discardableResult
    public func update(
        _ body: (inout WorldSyncMetadata) throws -> Void
    ) throws -> WorldSyncMetadata {
        try withLock {
            var metadata = try loadUnlocked()
            let before = metadata
            try body(&metadata)
            if metadata != before {
                try saveUnlocked(metadata)
            }
            return metadata
        }
    }

    /// CKAsset requires a file URL. Payloads are recreated from durable pending
    /// metadata when needed; these exact files are disposable transport copies.
    public func writeAsset(_ data: Data, revision: UUID) throws -> URL {
        guard Int64(data.count) <= Self.maximumAssetBytes else {
            throw WorldSyncMetadataError.assetTooLarge
        }
        return try withLock {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = assetURL(revision: revision)
            try rejectUnsafeTarget(url)
            try atomicWrite(data, to: url)
            return url
        }
    }

    public func removeAsset(revision: UUID) throws {
        try withLock {
            let url = assetURL(revision: revision)
            if unlink(url.path) != 0, errno != ENOENT {
                throw WorldSyncMetadataError.cannotDelete(Self.posixMessage())
            }
        }
    }

    /// Remove the state and exact UUID-named transport assets. The lock file is
    /// retained so an active process never races a replacement lock inode.
    public func deleteOwnedData() throws {
        try withLock {
            var failures: [String] = []
            if unlink(stateURL.path) != 0, errno != ENOENT {
                failures.append("state.json: \(Self.posixMessage())")
            }
            if FileManager.default.fileExists(atPath: root.path) {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                for url in urls where Self.isOwnedAsset(url) {
                    if unlink(url.path) != 0, errno != ENOENT {
                        failures.append("\(url.lastPathComponent): \(Self.posixMessage())")
                    }
                }
            }
            if !failures.isEmpty {
                throw WorldSyncMetadataError.cannotDelete(failures.joined(separator: "; "))
            }
        }
    }

    private func loadUnlocked() throws -> WorldSyncMetadata {
        guard let data = try readBoundedFile(stateURL, maximum: Self.maximumStateBytes) else {
            return WorldSyncMetadata()
        }
        let metadata: WorldSyncMetadata
        do {
            metadata = try JSONDecoder.flowmo.decode(WorldSyncMetadata.self, from: data)
        } catch {
            throw WorldSyncMetadataError.cannotDecode
        }
        try validate(metadata)
        return metadata
    }

    private func saveUnlocked(_ metadata: WorldSyncMetadata) throws {
        try validate(metadata)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try rejectUnsafeTarget(stateURL)
        let data = try JSONEncoder.flowmo.encode(metadata)
        guard Int64(data.count) <= Self.maximumStateBytes else {
            throw WorldSyncMetadataError.stateTooLarge
        }
        try atomicWrite(data, to: stateURL)
    }

    private func validate(_ metadata: WorldSyncMetadata) throws {
        guard metadata.schemaVersion == WorldSyncMetadata.schemaVersion else {
            throw WorldSyncMetadataError.unsupportedSchema(metadata.schemaVersion)
        }
        if let account = metadata.accountRecordName,
            account.utf8.count > 1_024
        {
            throw WorldSyncMetadataError.invalidMetadata
        }
        if let deletionAccount = metadata.cloudDeletionAccountRecordName,
            deletionAccount.utf8.count > 1_024
        {
            throw WorldSyncMetadataError.invalidMetadata
        }
        guard metadata.cloudDeletionAccountRecordName == nil || metadata.cloudDeletionPending,
            !metadata.cloudDeletionPending || metadata.pending != nil
        else {
            throw WorldSyncMetadataError.invalidMetadata
        }
        guard
            metadata.pendingDeletionRecordNames.count
                == Set(metadata.pendingDeletionRecordNames).count
        else {
            throw WorldSyncMetadataError.invalidMetadata
        }
        let snapshots = [
            metadata.base, metadata.pending, metadata.conflict?.local, metadata.conflict?.remote,
            metadata.conflict?.ancestor,
        ].compactMap { $0 }
        for snapshot in snapshots {
            _ = try snapshot.applying(to: .empty)
        }
        if let head = metadata.remoteHeadData {
            guard Int64(head.count) <= Self.maximumAssetBytes else {
                throw WorldSyncMetadataError.assetTooLarge
            }
            _ = try WorldSyncRecordCodec.decodeHead(head)
        }
        guard metadata.remoteSessionData.count <= WorldPersistenceLimits.maximumHistoryCount,
            metadata.recordSystemFields.count <= WorldPersistenceLimits.maximumHistoryCount + 1,
            metadata.pendingRevisions.count <= WorldPersistenceLimits.maximumHistoryCount + 1,
            metadata.pendingDeletionRecordNames.count <= WorldPersistenceLimits.maximumHistoryCount
        else {
            throw WorldSyncMetadataError.invalidMetadata
        }
        for (name, data) in metadata.remoteSessionData {
            guard Int64(data.count) <= Self.maximumAssetBytes else {
                throw WorldSyncMetadataError.assetTooLarge
            }
            _ = try WorldSyncRecordCodec.decodeSession(data, recordName: name)
        }
        for name in metadata.recordSystemFields.keys where !Self.isKnownRecordName(name) {
            throw WorldSyncMetadataError.invalidMetadata
        }
        for name in metadata.pendingRevisions.keys where !Self.isKnownRecordName(name) {
            throw WorldSyncMetadataError.invalidMetadata
        }
        for name in metadata.pendingDeletionRecordNames
        where name == WorldSyncRecordCodec.headRecordName || !Self.isKnownRecordName(name) {
            throw WorldSyncMetadataError.invalidMetadata
        }
    }

    private func assetURL(revision: UUID) -> URL {
        root.appendingPathComponent("asset-\(revision.uuidString.lowercased()).json")
    }

    private static func isOwnedAsset(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix("asset-"), name.hasSuffix(".json") else { return false }
        let token = name.dropFirst("asset-".count).dropLast(".json".count)
        return UUID(uuidString: String(token)) != nil
    }

    private static func isKnownRecordName(_ name: String) -> Bool {
        name == WorldSyncRecordCodec.headRecordName
            || WorldSyncRecordCodec.sessionID(recordName: name) != nil
    }

    private func readBoundedFile(_ url: URL, maximum: Int64) throws -> Data? {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw WorldSyncMetadataError.cannotRead(Self.posixMessage())
        }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            info.st_nlink == 1,
            info.st_size >= 0,
            info.st_size <= maximum
        else {
            throw WorldSyncMetadataError.unsafeTarget
        }
        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fd, bytes.baseAddress, min(bytes.count, Int(maximum) + 1 - data.count))
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw WorldSyncMetadataError.cannotRead(Self.posixMessage())
            }
            data.append(contentsOf: buffer.prefix(count))
            guard Int64(data.count) <= maximum else {
                throw WorldSyncMetadataError.stateTooLarge
            }
        }
        return data
    }

    private func rejectUnsafeTarget(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_nlink == 1 else {
                throw WorldSyncMetadataError.unsafeTarget
            }
            return
        }
        guard errno == ENOENT else {
            throw WorldSyncMetadataError.cannotRead(Self.posixMessage())
        }
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = root.appendingPathComponent(".sync-write-\(UUID().uuidString).tmp")
        let fd = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard fd >= 0 else { throw WorldSyncMetadataError.cannotWrite(Self.posixMessage()) }
        var keepTemporary = true
        defer {
            close(fd)
            if keepTemporary { _ = unlink(temporary.path) }
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw WorldSyncMetadataError.cannotWrite(Self.posixMessage())
                }
                guard count > 0 else {
                    throw WorldSyncMetadataError.cannotWrite("write returned zero bytes")
                }
                offset += count
            }
        }
        guard fsync(fd) == 0, rename(temporary.path, destination.path) == 0 else {
            throw WorldSyncMetadataError.cannotWrite(Self.posixMessage())
        }
        keepTemporary = false
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = open(
            lockURL.path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard fd >= 0 else { throw WorldSyncMetadataError.cannotLock(Self.posixMessage()) }
        var info = stat()
        guard fstat(fd, &info) == 0,
            (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            info.st_nlink == 1
        else {
            close(fd)
            throw WorldSyncMetadataError.cannotLock("sync.lock must be a private regular file")
        }
        let locked = flock(fd, LOCK_EX)
        defer {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }
        guard locked == 0 else { throw WorldSyncMetadataError.cannotLock(Self.posixMessage()) }
        return try body()
    }

    private static func posixMessage() -> String {
        String(cString: strerror(errno))
    }
}

public enum WorldSyncMetadataError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case stateTooLarge
    case assetTooLarge
    case invalidMetadata
    case unsafeTarget
    case cannotRead(String)
    case cannotWrite(String)
    case cannotDelete(String)
    case cannotLock(String)
    case cannotDecode

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "Unsupported Flowmo sync metadata schema \(version)."
        case .stateTooLarge: return "Flowmo sync metadata is too large."
        case .assetTooLarge: return "Flowmo sync payload is too large."
        case .invalidMetadata: return "Flowmo sync metadata is invalid."
        case .unsafeTarget: return "Flowmo sync storage target is unsafe."
        case .cannotRead(let reason): return "Could not read Flowmo sync metadata: \(reason)."
        case .cannotWrite(let reason): return "Could not write Flowmo sync metadata: \(reason)."
        case .cannotDelete(let reason): return "Could not delete Flowmo sync metadata: \(reason)."
        case .cannotLock(let reason): return "Could not lock Flowmo sync metadata: \(reason)."
        case .cannotDecode: return "Could not decode Flowmo sync metadata."
        }
    }
}
