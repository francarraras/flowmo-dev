import CloudKit
import Combine
import FlowmoCore
import Foundation

#if os(macOS)
    import Security
#endif

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

    package func update(
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
        container: CKContainer,
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

    /// Creates the production adapter only when this process is signed for the
    /// configured iCloud container. CloudKit traps while constructing a named
    /// container in an unentitled macOS process, so this check must happen first.
    @MainActor
    public static func makeDefault(
        store: Store,
        status: WorldSyncStatus,
        onWorldChange: @escaping @MainActor @Sendable (World) -> Void = { _ in }
    ) -> CloudWorldSync? {
        guard currentProcessHasContainerEntitlement else {
            status.markUnavailable(issueCode: "sync_entitlement_unavailable")
            return nil
        }
        do {
            return try CloudWorldSync(
                store: store,
                container: CKContainer(identifier: containerIdentifier),
                status: status,
                onWorldChange: onWorldChange
            )
        } catch {
            status.markUnavailable()
            return nil
        }
    }

    public static var currentProcessHasContainerEntitlement: Bool {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil) else { return false }
            let key = "com.apple.developer.icloud-container-identifiers" as CFString
            let value = SecTaskCopyValueForEntitlement(task, key, nil)
            return containerIdentifiers(from: value).contains(containerIdentifier)
        #else
            // iOS builds carrying this target are provisioned through the app
            // target. Xcode rejects unsupported iCloud capabilities before run.
            return true
        #endif
    }

    static func containerIdentifiers(from entitlement: Any?) -> [String] {
        entitlement as? [String] ?? []
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

    public func resolveConflict(
        _ conflict: WorldSyncConflict,
        choosing choice: WorldSyncChoice
    ) {
        let engine = engine
        Task {
            await state.resolveConflict(
                conflict,
                choosing: choice,
                engine: engine
            )
        }
    }

    /// Removes local sync replicas immediately and queues deletion of the
    /// private CloudKit copy. `completion` is false when that cloud work remains
    /// durable but could not be confirmed during this attempt.
    public func deleteAllData(
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let engine = engine
        Task {
            let complete = await state.deleteAllData(engine: engine)
            await completion(complete)
        }
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
    private let localPersistence: WorldSyncLocalPersistence
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
        localPersistence = WorldSyncLocalPersistence(
            worldStore: worldStore,
            metadataStore: metadataStore
        )
        self.metadata = metadata
        self.status = status
        self.onWorldChange = onWorldChange
    }

    func start(engine: CKSyncEngine) async {
        await publish(phase: .syncing)
        if metadata.base == nil && metadata.recordSystemFields.isEmpty {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            do {
                try await engine.sendChanges(.init(scope: .all))
            } catch {
                await publish(phase: .unavailable, issueCode: Self.issueCode(error))
                return
            }
        }
        if metadata.canSendCloudDeletion,
            metadata.pending != nil || !metadata.pendingDeletionRecordNames.isEmpty
        {
            do {
                try enqueuePending(on: engine, refreshingRevisions: false)
            } catch {
                await publish(phase: .unavailable, issueCode: Self.issueCode(error))
                return
            }
        }
        await refresh(engine: engine)
    }

    func refresh(engine: CKSyncEngine) async {
        do {
            try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
            guard try await processRemote(engine: engine) else { return }
            if metadata.canSendCloudDeletion,
                metadata.pending != nil || !metadata.pendingDeletionRecordNames.isEmpty
            {
                try await engine.sendChanges(.init(scope: .zoneIDs([zoneID])))
            } else if metadata.conflict == nil, !metadata.cloudDeletionPending {
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
            if metadata.cloudDeletionPending, !metadata.canSendCloudDeletion {
                metadata.pending = snapshot
                try metadataStore.save(metadata)
                await publish(phase: .unavailable, issueCode: "sync_deletion_account_unavailable")
                return
            }
            try metadataStore.save(metadata)
            try await stage(snapshot, on: engine)
        } catch {
            await publish(phase: .unavailable, issueCode: Self.issueCode(error))
        }
    }

    func resolveConflict(
        _ conflict: WorldSyncConflict,
        choosing choice: WorldSyncChoice,
        engine: CKSyncEngine
    ) async {
        do {
            let commit = try localPersistence.commit {
                currentWorld, nextMetadata in
                try WorldSyncRemotePlanner.resolveDisplayedConflict(
                    conflict,
                    choosing: choice,
                    currentWorld: currentWorld,
                    metadata: &nextMetadata
                )
            }
            metadata = commit.metadata

            switch commit.output {
            case .staleWorld:
                _ = try await processRemote(engine: engine, reconcileExistingConflict: true)
            case .staleConflict:
                _ = try await processRemote(engine: engine)
            case .staleRemote:
                _ = try await processRemote(engine: engine, reconcileExistingConflict: true)
            case .resolved(let resolved, let shouldStage):
                do {
                    if shouldStage {
                        try await stage(resolved, on: engine)
                    } else {
                        await publish(phase: .synced)
                    }
                } catch {
                    await publishUnavailable(
                        error,
                        committedWorld: commit.world,
                        shouldNotify: true
                    )
                    return
                }
                guard (try? worldStore.load()) == commit.world else { return }
                await onWorldChange(commit.world)
            }
        } catch {
            if let latestMetadata = try? metadataStore.load() {
                metadata = latestMetadata
            }
            if let latestWorld = try? worldStore.load() {
                await publishUnavailable(
                    error,
                    committedWorld: latestWorld,
                    shouldNotify: true
                )
                return
            }
            await publish(phase: .unavailable, issueCode: Self.issueCode(error))
        }
    }

    func deleteAllData(engine: CKSyncEngine) async -> Bool {
        do {
            metadata.prepareDataDeletion()
            try metadataStore.save(metadata)
            guard metadata.canSendCloudDeletion else {
                await publish(
                    phase: .unavailable,
                    issueCode: "sync_deletion_account_unavailable"
                )
                return false
            }
            try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
            guard try await processRemote(engine: engine) else { return false }
            try await engine.sendChanges(.init(scope: .zoneIDs([zoneID])))
            let complete =
                !metadata.cloudDeletionPending && metadata.pending == nil
                && metadata.pendingDeletionRecordNames.isEmpty
            if complete {
                await publish(phase: .synced)
            } else {
                await publish(phase: .unavailable, issueCode: "sync_deletion_pending")
            }
            return complete
        } catch {
            await publish(phase: .unavailable, issueCode: "sync_deletion_pending")
            return false
        }
    }

    func handle(event: CKSyncEngine.Event, engine: CKSyncEngine) async {
        do {
            switch event {
            case .stateUpdate(let update):
                metadata.engineState = try JSONEncoder.flowmo.encode(update.stateSerialization)
                try metadataStore.save(metadata)
            case .accountChange(let change):
                try await handleAccountChange(change, engine: engine)
            case .fetchedRecordZoneChanges(let fetched):
                for modification in fetched.modifications where modification.record.recordID.zoneID == zoneID {
                    try ingest(modification.record)
                }
                for deletion in fetched.deletions where deletion.recordID.zoneID == zoneID {
                    removeRemoteRecord(named: deletion.recordID.recordName)
                }
                try metadataStore.save(metadata)
            case .didFetchChanges:
                _ = try await processRemote(engine: engine)
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
                if !metadata.cloudDeletionPending && metadata.pending == nil && metadata.conflict == nil
                    && metadata.pendingDeletionRecordNames.isEmpty
                {
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

    private func handleAccountChange(
        _ change: CKSyncEngine.Event.AccountChange,
        engine: CKSyncEngine
    ) async throws {
        switch change.changeType {
        case .signIn(let currentUser):
            let current = currentUser.recordName
            if let previous = metadata.accountRecordName, previous != current {
                metadata.prepareForAccountSwitch(to: current)
            } else {
                metadata.accountRecordName = current
                if metadata.cloudDeletionPending,
                    metadata.cloudDeletionAccountRecordName == nil
                {
                    metadata.cloudDeletionAccountRecordName = current
                }
            }
        case .signOut:
            await publish(phase: .localOnly)
        case .switchAccounts(_, let currentUser):
            metadata.prepareForAccountSwitch(to: currentUser.recordName)
        @unknown default:
            throw WorldSyncTransportError.invalidRecord
        }
        let stale = engine.state.pendingRecordZoneChanges.filter {
            Self.belongsToFlowmoZone($0, zoneID: zoneID)
        }
        engine.state.remove(pendingRecordZoneChanges: stale)
        try metadataStore.save(metadata)
    }

    private func processRemote(
        engine: CKSyncEngine,
        reconcileExistingConflict: Bool = false
    ) async throws -> Bool {
        let commit: WorldSyncLocalCommit<WorldSyncRemoteProcessing>
        do {
            commit = try localPersistence.commit { currentWorld, nextMetadata in
                try WorldSyncRemotePlanner.process(
                    currentWorld: currentWorld,
                    metadata: &nextMetadata,
                    reconcileExistingConflict: reconcileExistingConflict
                )
            }
        } catch {
            if let latestMetadata = try? metadataStore.load() {
                metadata = latestMetadata
            }
            guard let latestWorld = try? worldStore.load() else { throw error }
            await publishUnavailable(
                error,
                committedWorld: latestWorld,
                shouldNotify: true
            )
            return false
        }
        metadata = commit.metadata

        switch commit.output {
        case .deletionAccountUnavailable:
            removePendingZoneChanges(from: engine)
            await publish(phase: .unavailable, issueCode: "sync_deletion_account_unavailable")
        case .deletionPending:
            try enqueuePending(on: engine, refreshingRevisions: true)
            await publish(phase: .syncing)
        case .conflict(let conflict):
            removePendingZoneChanges(from: engine)
            try enqueuePending(on: engine, refreshingRevisions: false)
            await publish(phase: .needsChoice, conflict: conflict)
        case .merged(let merged, let remote):
            do {
                if merged != remote {
                    try await stage(merged, on: engine)
                } else if metadata.pendingDeletionRecordNames.isEmpty {
                    await publish(phase: .synced)
                } else {
                    try enqueuePending(on: engine, refreshingRevisions: false)
                    await publish(phase: .syncing)
                }
            } catch {
                await publishUnavailable(
                    error,
                    committedWorld: commit.world,
                    shouldNotify: commit.worldChanged
                )
                return false
            }
            if commit.worldChanged, (try? worldStore.load()) == commit.world {
                await onWorldChange(commit.world)
            }
        }
        return true
    }

    /// Publish transport failure before crossing to the UI actor. If the World
    /// commit is still current, the UI adopts that durable result even though
    /// its corresponding cloud staging failed.
    private func publishUnavailable(
        _ error: Error,
        committedWorld: World,
        shouldNotify: Bool
    ) async {
        await publish(phase: .unavailable, issueCode: Self.issueCode(error))
        guard shouldNotify, (try? worldStore.load()) == committedWorld else { return }
        await onWorldChange(committedWorld)
    }

    private func removePendingZoneChanges(from engine: CKSyncEngine) {
        let stale = engine.state.pendingRecordZoneChanges.filter {
            Self.belongsToFlowmoZone($0, zoneID: zoneID)
        }
        engine.state.remove(pendingRecordZoneChanges: stale)
    }

    private func stage(_ snapshot: WorldSyncSnapshot, on engine: CKSyncEngine) async throws {
        metadata.pending = snapshot
        metadata.generation = snapshot.head.generation
        try enqueuePending(on: engine, refreshingRevisions: true)
        await publish(phase: .syncing)
    }

    private func enqueuePending(on engine: CKSyncEngine, refreshingRevisions: Bool) throws {
        let pendingRecords = try metadata.pending.map(WorldSyncRecordCodec.records(for:)) ?? []
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
        let derivedDeletions =
            metadata.pending == nil
            ? []
            : baseByName.keys.filter {
                pendingByName[$0] == nil && $0 != WorldSyncRecordCodec.headRecordName
            }
        var deletionNames = Set(metadata.pendingDeletionRecordNames)
        deletionNames.formUnion(derivedDeletions)
        deletionNames.subtract(pendingByName.keys)
        metadata.pendingDeletionRecordNames = deletionNames.sorted()
        let deletions = metadata.pendingDeletionRecordNames.map {
            CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID($0))
        }

        metadata.pendingRevisions = metadata.pendingRevisions.filter { pendingByName[$0.key] != nil }
        try metadataStore.save(metadata)
        engine.state.add(pendingRecordZoneChanges: saves + deletions)
        if saves.isEmpty, deletions.isEmpty, let pending = metadata.pending {
            metadata.base = pending
            metadata.pending = nil
            metadata.pendingRevisions = [:]
            try metadataStore.save(metadata)
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
        var savedHead = false
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
            savedHead = savedHead || name == WorldSyncRecordCodec.headRecordName
        }
        for id in sent.deletedRecordIDs where id.zoneID == zoneID {
            metadata.pendingDeletionRecordNames.removeAll { $0 == id.recordName }
            metadata.recordSystemFields.removeValue(forKey: id.recordName)
            removeRemoteRecord(named: id.recordName)
        }
        if savedHead,
            let pending = metadata.pending,
            metadata.pendingRevisions[WorldSyncRecordCodec.headRecordName] == nil,
            metadata.pendingDeletionRecordNames.isEmpty
        {
            metadata.base = pending
            try metadata.replaceRemote(with: pending)
            metadata.pending = nil
            metadata.pendingRevisions = [:]
            metadata.cloudDeletionPending = false
            metadata.cloudDeletionAccountRecordName = nil
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
                try enqueuePending(on: engine, refreshingRevisions: false)
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
            if cloud.code == .notAuthenticated {
                return "sync_account_unavailable"
            }
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
