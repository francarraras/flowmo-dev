import CloudKit
import Combine
import FlowmoCore
import Foundation

public enum WorldSyncPhase: String, Equatable, Sendable {
    case localOnly
    case syncing
    case synced
    case needsChoice
    case unavailable
}

@MainActor
public final class WorldSyncStatus: ObservableObject {
    @Published public fileprivate(set) var phase: WorldSyncPhase = .localOnly
    @Published public fileprivate(set) var conflict: WorldSyncConflict?
    @Published public fileprivate(set) var issueCode: String?

    public init() {}

    public func markUnavailable(issueCode: String = "sync_metadata_unavailable") {
        update(phase: .unavailable, issueCode: issueCode)
    }

    fileprivate func update(
        phase: WorldSyncPhase,
        conflict: WorldSyncConflict? = nil,
        issueCode: String? = nil
    ) {
        self.phase = phase
        self.conflict = conflict
        self.issueCode = issueCode
    }
}

public final class CloudWorldSync: NSObject, CKSyncEngineDelegate, @unchecked Sendable {
    public static let containerIdentifier = "iCloud.app.flowmo"
    public static let zoneName = "FlowmoWorld"

    public let status: WorldSyncStatus

    private let state: CloudWorldSyncState
    private let database: CKDatabase
    private let initialStateSerialization: CKSyncEngine.State.Serialization?

    private lazy var engine: CKSyncEngine = {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: initialStateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = "flowmo-world-sync-v1"
        return CKSyncEngine(configuration)
    }()

    @MainActor
    public init(
        store: Store,
        container: CKContainer = CKContainer(identifier: CloudWorldSync.containerIdentifier),
        status: WorldSyncStatus? = nil,
        onWorldChange: @escaping @MainActor @Sendable (World) -> Void = { _ in }
    ) throws {
        let metadataStore = WorldSyncMetadataStore(root: store.root)
        let metadata = try metadataStore.load()
        if let encoded = metadata.engineState {
            initialStateSerialization = try JSONDecoder.flowmo.decode(
                CKSyncEngine.State.Serialization.self,
                from: encoded
            )
        } else {
            initialStateSerialization = nil
        }
        let resolvedStatus = status ?? WorldSyncStatus()
        self.status = resolvedStatus
        database = container.privateCloudDatabase
        state = CloudWorldSyncState(
            worldStore: store,
            metadataStore: metadataStore,
            metadata: metadata,
            status: resolvedStatus,
            onWorldChange: onWorldChange
        )
        super.init()
    }

    public func start() {
        let engine = engine
        Task { await state.start(engine: engine) }
    }

    public func refresh() {
        let engine = engine
        Task { await state.refresh(engine: engine) }
    }

    public func localWorldDidChange(takesOwnership: Bool = true) {
        let engine = engine
        Task { await state.localWorldDidChange(takesOwnership: takesOwnership, engine: engine) }
    }

    public func resolveConflict(choosing choice: WorldSyncChoice) {
        let engine = engine
        Task { await state.resolveConflict(choosing: choice, engine: engine) }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await state.handle(event: event, engine: syncEngine)
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await state.nextRecordZoneChangeBatch(context, engine: syncEngine)
    }
}

private actor CloudWorldSyncState {
    private static let revisionKey = "revision"
    private static let payloadKey = "payload"
    private static let schemaVersionKey = "schemaVersion"

    private let worldStore: Store
    private let metadataStore: WorldSyncMetadataStore
    private let status: WorldSyncStatus
    private let onWorldChange: @MainActor @Sendable (World) -> Void
    private let zoneID = CKRecordZone.ID(zoneName: CloudWorldSync.zoneName, ownerName: CKCurrentUserDefaultName)
    private var metadata: WorldSyncMetadata

    init(
        worldStore: Store,
        metadataStore: WorldSyncMetadataStore,
        metadata: WorldSyncMetadata,
        status: WorldSyncStatus,
        onWorldChange: @escaping @MainActor @Sendable (World) -> Void
    ) {
        self.worldStore = worldStore
        self.metadataStore = metadataStore
        self.metadata = metadata
        self.status = status
        self.onWorldChange = onWorldChange
    }

    func start(engine: CKSyncEngine) async {
        await publish(phase: .syncing)
        if metadata.base == nil && metadata.recordSystemFields.isEmpty {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        if metadata.pending != nil {
            await enqueuePending(on: engine, refreshingRevisions: false)
        }
        await refresh(engine: engine)
    }

    func refresh(engine: CKSyncEngine) async {
        do {
            try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
            try await processRemote(engine: engine)
            if metadata.pending != nil {
                try await engine.sendChanges(.init(scope: .zoneIDs([zoneID])))
            } else if metadata.conflict == nil {
                await publish(phase: .synced)
            }
        } catch {
            await publish(phase: .unavailable, issueCode: Self.issueCode(error))
        }
    }

    func localWorldDidChange(takesOwnership: Bool, engine: CKSyncEngine) async {
        guard metadata.conflict == nil else { return }
        do {
            let world = try worldStore.load()
            let snapshot = WorldSyncSnapshot(world: world, generation: metadata.generation)
            if snapshot == metadata.pending || snapshot == metadata.base {
                return
            }
            if takesOwnership {
                metadata.remoteLiveSessionID = nil
            }
            try metadataStore.save(metadata)
            await stage(snapshot, on: engine)
        } catch {
            await publish(phase: .unavailable, issueCode: Self.issueCode(error))
        }
    }

    func resolveConflict(choosing choice: WorldSyncChoice, engine: CKSyncEngine) async {
        guard let conflict = metadata.conflict else { return }
        do {
            let resolved = WorldSyncReconciler.resolve(conflict, choosing: choice)
            let cloudSide = conflict.remote
            metadata.conflict = nil
            metadata.accountChangeRequiresChoice = false
            metadata.generation = resolved.head.generation
            metadata.remoteLiveSessionID = choice == .remote ? resolved.head.live?.id : nil
            metadata.base = cloudSide
            let applied = try resolved.applying(to: worldStore.load())
            try metadataStore.save(metadata)
            try worldStore.save(applied)
            await onWorldChange(applied)
            if choice == .local || resolved != cloudSide {
                await stage(resolved, on: engine)
            } else {
                metadata.base = resolved
                metadata.pending = nil
                metadata.pendingRevisions = [:]
                try metadataStore.save(metadata)
                await publish(phase: .synced)
            }
        } catch {
            await publish(phase: .unavailable, issueCode: Self.issueCode(error))
        }
    }

    func handle(event: CKSyncEngine.Event, engine: CKSyncEngine) async {
        do {
            switch event {
            case .stateUpdate(let update):
                metadata.engineState = try JSONEncoder.flowmo.encode(update.stateSerialization)
                try metadataStore.save(metadata)
            case .accountChange(let change):
                try await handleAccountChange(change)
            case .fetchedRecordZoneChanges(let fetched):
                for modification in fetched.modifications where modification.record.recordID.zoneID == zoneID {
                    try ingest(modification.record)
                }
                for deletion in fetched.deletions where deletion.recordID.zoneID == zoneID {
                    removeRemoteRecord(named: deletion.recordID.recordName)
                }
                try metadataStore.save(metadata)
            case .didFetchChanges:
                try await processRemote(engine: engine)
            case .sentDatabaseChanges(let sent):
                for failure in sent.failedZoneSaves where failure.zone.zoneID == zoneID {
                    await publish(phase: .unavailable, issueCode: Self.issueCode(failure.error))
                }
            case .sentRecordZoneChanges(let sent):
                try await handleSentRecordChanges(sent, engine: engine)
            case .fetchedDatabaseChanges(let fetched):
                if fetched.deletions.contains(where: { $0.zoneID == zoneID }) {
                    metadata.remoteHeadData = nil
                    metadata.remoteSessionData = [:]
                    metadata.recordSystemFields = [:]
                    try metadataStore.save(metadata)
                }
            case .didSendChanges:
                if metadata.pending == nil && metadata.conflict == nil {
                    await publish(phase: .synced)
                }
            case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
                .willSendChanges:
                break
            @unknown default:
                await publish(phase: .unavailable, issueCode: "sync_event_unsupported")
            }
        } catch {
            await publish(phase: .unavailable, issueCode: Self.issueCode(error))
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        engine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        do {
            var batch = await CKSyncEngine.RecordZoneChangeBatch(
                pendingChanges: changes
            ) { [weak self] recordID in
                guard let self else { return nil }
                return try? await self.recordToSave(recordID)
            }
            batch?.atomicByZone = true
            return batch
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) async throws {
        switch change.changeType {
        case .signIn(let currentUser):
            let current = currentUser.recordName
            if let previous = metadata.accountRecordName, previous != current {
                prepareForAccountSwitch(to: current)
            } else {
                metadata.accountRecordName = current
            }
        case .signOut:
            await publish(phase: .localOnly)
        case .switchAccounts(_, let currentUser):
            prepareForAccountSwitch(to: currentUser.recordName)
        @unknown default:
            throw WorldSyncTransportError.invalidRecord
        }
        try metadataStore.save(metadata)
    }

    private func prepareForAccountSwitch(to account: String) {
        metadata.accountRecordName = account
        metadata.accountChangeRequiresChoice = true
        metadata.engineState = nil
        metadata.base = nil
        metadata.pending = nil
        metadata.conflict = nil
        metadata.remoteHeadData = nil
        metadata.remoteSessionData = [:]
        metadata.recordSystemFields = [:]
        metadata.pendingRevisions = [:]
        metadata.remoteLiveSessionID = nil
    }

    private func processRemote(engine: CKSyncEngine) async throws {
        let localWorld = try worldStore.load()
        let local = WorldSyncSnapshot(world: localWorld, generation: metadata.generation)
        let remote = try metadata.remoteSnapshot
        let outcome: WorldSyncReconciliation

        if metadata.accountChangeRequiresChoice {
            let cloud = remote ?? WorldSyncSnapshot(world: .empty, generation: UUID())
            outcome = .conflict(
                WorldSyncConflict(kind: .account, local: local, remote: cloud, ancestor: nil)
            )
        } else if let base = metadata.base {
            if let remote {
                outcome = WorldSyncReconciler.reconcile(local: local, remote: remote, ancestor: base)
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
            try metadataStore.save(metadata)
            await publish(phase: .needsChoice, conflict: conflict)
        case .merged(let merged):
            let remoteChangedLive = merged.head.live != local.head.live
            metadata.generation = merged.head.generation
            metadata.base = remote ?? merged
            metadata.remoteLiveSessionID = remoteChangedLive ? merged.head.live?.id : metadata.remoteLiveSessionID
            let applied = try merged.applying(to: localWorld)
            try metadataStore.save(metadata)
            if applied != localWorld {
                try worldStore.save(applied)
                await onWorldChange(applied)
            }
            if merged != remote {
                await stage(merged, on: engine)
            } else {
                metadata.pending = nil
                metadata.pendingRevisions = [:]
                try metadataStore.save(metadata)
                await publish(phase: .synced)
            }
        }
    }

    private func stage(_ snapshot: WorldSyncSnapshot, on engine: CKSyncEngine) async {
        metadata.pending = snapshot
        metadata.generation = snapshot.head.generation
        await enqueuePending(on: engine, refreshingRevisions: true)
        await publish(phase: .syncing)
    }

    private func enqueuePending(on engine: CKSyncEngine, refreshingRevisions: Bool) async {
        do {
            guard let pending = metadata.pending else { return }
            let pendingRecords = try WorldSyncRecordCodec.records(for: pending)
            let baseRecords = try metadata.base.map(WorldSyncRecordCodec.records(for:)) ?? []
            let pendingByName = Dictionary(uniqueKeysWithValues: pendingRecords.map { ($0.name, $0) })
            let baseByName = Dictionary(uniqueKeysWithValues: baseRecords.map { ($0.name, $0) })

            let existing = engine.state.pendingRecordZoneChanges.filter { Self.belongsToFlowmoZone($0, zoneID: zoneID) }
            engine.state.remove(pendingRecordZoneChanges: existing)

            var saves: [CKSyncEngine.PendingRecordZoneChange] = []
            let changedSessions = pendingRecords.filter {
                $0.kind == .completedSession && baseByName[$0.name]?.data != $0.data
            }
            for payload in changedSessions {
                if refreshingRevisions || metadata.pendingRevisions[payload.name] == nil {
                    metadata.pendingRevisions[payload.name] = UUID()
                }
                saves.append(.saveRecord(recordID(payload.name)))
            }
            if let head = pendingByName[WorldSyncRecordCodec.headRecordName],
                baseByName[head.name]?.data != head.data
            {
                if refreshingRevisions || metadata.pendingRevisions[head.name] == nil {
                    metadata.pendingRevisions[head.name] = UUID()
                }
                saves.append(.saveRecord(recordID(head.name)))
            }
            let deletions = baseByName.keys
                .filter { pendingByName[$0] == nil && $0 != WorldSyncRecordCodec.headRecordName }
                .sorted()
                .map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID($0)) }

            metadata.pendingRevisions = metadata.pendingRevisions.filter { pendingByName[$0.key] != nil }
            try metadataStore.save(metadata)
            engine.state.add(pendingRecordZoneChanges: saves + deletions)
            if saves.isEmpty && deletions.isEmpty {
                metadata.base = pending
                metadata.pending = nil
                metadata.pendingRevisions = [:]
                try metadataStore.save(metadata)
            }
        } catch {
            await publish(phase: .unavailable, issueCode: Self.issueCode(error))
        }
    }

    private func recordToSave(_ id: CKRecord.ID) async throws -> CKRecord? {
        guard id.zoneID == zoneID,
            let pending = metadata.pending,
            let payload = try WorldSyncRecordCodec.records(for: pending).first(where: { $0.name == id.recordName }),
            let revision = metadata.pendingRevisions[id.recordName]
        else { return nil }

        let record: CKRecord
        if let fields = metadata.recordSystemFields[id.recordName],
            let decoded = try Self.decodeSystemFields(fields)
        {
            record = decoded
        } else {
            record = CKRecord(recordType: payload.kind.rawValue, recordID: id)
        }
        guard record.recordID == id, record.recordType == payload.kind.rawValue else { return nil }
        let assetURL = try metadataStore.writeAsset(payload.data, revision: revision)
        record[Self.schemaVersionKey] = WorldSyncHead.schemaVersion as CKRecordValue
        record[Self.revisionKey] = revision.uuidString.lowercased() as CKRecordValue
        record[Self.payloadKey] = CKAsset(fileURL: assetURL)
        return record
    }

    private func handleSentRecordChanges(
        _ sent: CKSyncEngine.Event.SentRecordZoneChanges,
        engine: CKSyncEngine
    ) async throws {
        for record in sent.savedRecords where record.recordID.zoneID == zoneID {
            let name = record.recordID.recordName
            metadata.recordSystemFields[name] = try Self.encodeSystemFields(record)
            if let raw = record[Self.revisionKey] as? String,
                let revision = UUID(uuidString: raw)
            {
                try? metadataStore.removeAsset(revision: revision)
                if metadata.pendingRevisions[name] == revision {
                    metadata.pendingRevisions.removeValue(forKey: name)
                }
            }
            if name == WorldSyncRecordCodec.headRecordName,
                let pending = metadata.pending,
                metadata.pendingRevisions[name] == nil
            {
                metadata.base = pending
                try metadata.replaceRemote(with: pending)
                metadata.pending = nil
                metadata.pendingRevisions = [:]
            }
        }
        for id in sent.deletedRecordIDs where id.zoneID == zoneID {
            metadata.recordSystemFields.removeValue(forKey: id.recordName)
            removeRemoteRecord(named: id.recordName)
        }
        try metadataStore.save(metadata)

        var needsFetch = false
        for failure in sent.failedRecordSaves where failure.record.recordID.zoneID == zoneID {
            if failure.error.code == .serverRecordChanged {
                if let server = failure.error.serverRecord {
                    try ingest(server)
                }
                needsFetch = true
            } else if failure.error.code == .zoneNotFound {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                await enqueuePending(on: engine, refreshingRevisions: false)
            } else {
                await publish(phase: .unavailable, issueCode: Self.issueCode(failure.error))
            }
        }
        if needsFetch {
            try metadataStore.save(metadata)
            try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
        }
    }

    private func ingest(_ record: CKRecord) throws {
        guard record.recordID.zoneID == zoneID,
            let asset = record[Self.payloadKey] as? CKAsset,
            let url = asset.fileURL
        else { throw WorldSyncTransportError.invalidRecord }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber,
            size.int64Value >= 0,
            size.int64Value <= WorldSyncMetadataStore.maximumAssetBytes
        else { throw WorldSyncTransportError.payloadTooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard Int64(data.count) <= WorldSyncMetadataStore.maximumAssetBytes else {
            throw WorldSyncTransportError.payloadTooLarge
        }
        let name = record.recordID.recordName
        switch WorldSyncRecordKind(rawValue: record.recordType) {
        case .head:
            guard name == WorldSyncRecordCodec.headRecordName else {
                throw WorldSyncTransportError.invalidRecord
            }
            _ = try WorldSyncRecordCodec.decodeHead(data)
            metadata.remoteHeadData = data
        case .completedSession:
            _ = try WorldSyncRecordCodec.decodeSession(data, recordName: name)
            metadata.remoteSessionData[name] = data
        case nil:
            throw WorldSyncTransportError.invalidRecord
        }
        metadata.recordSystemFields[name] = try Self.encodeSystemFields(record)
    }

    private func removeRemoteRecord(named name: String) {
        if name == WorldSyncRecordCodec.headRecordName {
            metadata.remoteHeadData = nil
        } else {
            metadata.remoteSessionData.removeValue(forKey: name)
        }
        metadata.recordSystemFields.removeValue(forKey: name)
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    private func publish(
        phase: WorldSyncPhase,
        conflict: WorldSyncConflict? = nil,
        issueCode: String? = nil
    ) async {
        await status.update(phase: phase, conflict: conflict, issueCode: issueCode)
    }

    private static func belongsToFlowmoZone(
        _ change: CKSyncEngine.PendingRecordZoneChange,
        zoneID: CKRecordZone.ID
    ) -> Bool {
        switch change {
        case .saveRecord(let id), .deleteRecord(let id): return id.zoneID == zoneID
        @unknown default: return false
        }
    }

    private static func encodeSystemFields(_ record: CKRecord) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func decodeSystemFields(_ data: Data) throws -> CKRecord? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    private static func issueCode(_ error: Error) -> String {
        if let cloud = error as? CKError {
            return "cloudkit_\(cloud.code.rawValue)"
        }
        if error is WorldSyncRecordError { return "sync_record_invalid" }
        if error is WorldSyncMetadataError { return "sync_metadata_unavailable" }
        return "sync_failed"
    }
}

public enum WorldSyncTransportError: LocalizedError, Equatable {
    case invalidRecord
    case payloadTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidRecord: return "Cloud data contains an invalid Flowmo record."
        case .payloadTooLarge: return "Cloud data contains an oversized Flowmo payload."
        }
    }
}
