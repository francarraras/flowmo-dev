import Combine
import FlowmoCore
import FlowmoSync
import Foundation

#if canImport(WidgetKit)
    import WidgetKit
#endif

public enum PhoneStoreConfigurationError: LocalizedError {
    case missingSharedAppGroup

    public var errorDescription: String? {
        "Flowmo configuration failure: App Group \"\(Store.phoneAppGroupID)\" is unavailable."
    }
}

@MainActor
public final class PhoneStoreBootstrap: ObservableObject {
    @Published public private(set) var controller: PhoneSessionController?
    private var lastUnavailableEmissionAt: Date?

    public init() {
        retry()
    }

    public func retry() {
        do {
            controller = PhoneSessionController(store: try PhoneSessionController.containerStore())
        } catch {
            controller = nil
            let timestamp = Date()
            if timestamp.timeIntervalSince(lastUnavailableEmissionAt ?? .distantPast) >= 60 {
                lastUnavailableEmissionAt = timestamp
                FlowmoDiagnosticLog.emit(.storeUnavailable, operation: .appGroup)
            }
        }
    }
}

@MainActor
public final class PhoneSessionController: ObservableObject {
    @Published public private(set) var world: World
    @Published public var now: Date = Date()
    @Published public var intentionDraft: String
    @Published public var captureDraft: String = ""
    @Published public var recallDraft: String = ""
    @Published public var showCapture: Bool = false
    @Published public var showParkedReview: Bool = false
    @Published public private(set) var storeNeedsRecovery = false
    @Published public private(set) var canPreserveAndReset = false
    @Published public var activeIssue: FlowmoPresentedIssue?
    @Published public private(set) var userNotice: String?
    @Published public private(set) var recentIssues: [FlowmoIssueRecord] = []
    public let syncStatus: WorldSyncStatus

    let store: Store
    let attention: PhoneAttention
    private let syncMetadataStore: WorldSyncMetadataStore
    private let worldAuthority: WorldAuthority
    private var cloudSync: CloudWorldSync?

    private var timer: Timer?
    private var applying = false
    private var sessionWasLive = false
    private var lastIssuePresentedAt: [FlowmoIssueCode: Date] = [:]
    private var cancellables = Set<AnyCancellable>()

    public var status: SessionStatus {
        Engine.sessionStatus(world, now: now)
    }

    public init(store: Store, attention: PhoneAttention = PhoneAttention()) {
        self.store = store
        self.attention = attention
        let syncMetadataStore = WorldSyncMetadataStore(root: store.root)
        self.syncMetadataStore = syncMetadataStore
        self.worldAuthority = WorldAuthority(
            store: store,
            syncMetadataStore: syncMetadataStore
        )
        self.syncStatus = WorldSyncStatus()
        var loaded: World
        var startupIssue: FlowmoIssueCode?
        do {
            loaded = try store.load()
        } catch {
            let timestamp = Date()
            loaded = .empty
            startupIssue = .storeUnreadable
            self.storeNeedsRecovery = true
            self.canPreserveAndReset = true
            self.recentIssues = [
                FlowmoIssueRecord(code: .storeUnreadable, operation: .load, occurredAt: timestamp)
            ]
            self.lastIssuePresentedAt[.storeUnreadable] = timestamp
            FlowmoDiagnosticLog.emit(.storeUnreadable, operation: .load)
        }
        var didRecover = false
        if startupIssue == nil,
            loaded.live?.isPaused == false,
            !syncMetadataStore.isRemoteLiveSession(loaded.live)
        {
            do {
                loaded = try store.update { engine in
                    engine.pauseUnpausedLiveOnProcessStart(now: Date())
                }.world
                didRecover = true
            } catch {
                startupIssue = FlowmoIssueClassifier.persistenceFailure(error)
                let code = startupIssue ?? .persistenceFailed
                let timestamp = Date()
                loaded = .empty
                self.storeNeedsRecovery = true
                self.canPreserveAndReset = code == .storeUnreadable
                self.recentIssues = [FlowmoIssueRecord(code: code, operation: .update, occurredAt: timestamp)]
                self.lastIssuePresentedAt[code] = timestamp
                FlowmoDiagnosticLog.emit(code, operation: .update)
            }
        }
        self.world = loaded
        self.intentionDraft = ""
        self.sessionWasLive = loaded.live != nil
        if loaded.live?.phase == .recall {
            self.recallDraft = loaded.live?.recallText ?? ""
        }
        if let startupIssue, startupIssue != .storeUnreadable {
            self.activeIssue = FlowmoPresentedIssue(code: startupIssue)
        }
        attention.reconcile(status: Engine.sessionStatus(loaded, now: Date()), cuesEnabled: loaded.config.cuesEnabled)
        syncStatus.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        if didRecover {
            reloadGlance()
        }
    }

    public func startRunning() {
        startCloudSync()
        attention.requestPermission()
        guard timer == nil else {
            becameActive()
            return
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        becameActive()
    }

    /// Background suspends the 0.25s timer. Catch up as soon as we are looking.
    public func becameActive() {
        tick()
        attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
        cloudSync?.refresh()
    }

    public func start() { apply(.start(intention: intentionDraft)) }

    public func skip() {
        guard let live = world.live else { return }
        apply(.skip, observed: ObservedLiveBeat(live))
    }

    public func stopFocus() {
        guard let live = world.live, live.phase == .focus, !live.isPaused else { return }
        apply(.stopFocus, observed: ObservedLiveBeat(live))
    }

    public func continueSession() {
        guard let live = world.live, live.isPaused else { return }
        _ = apply(
            .`continue`,
            observed: ObservedLiveBeat(live),
            warningPresentation: .syncMetadata
        )
    }

    public func restartSession() {
        guard let live = world.live, live.isPaused else { return }
        _ = apply(
            .restart,
            observed: ObservedLiveBeat(live),
            warningPresentation: .syncMetadata
        )
    }

    public func submitCapture() {
        let trimmed = captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let live = world.live,
            apply(.capture(trimmed), observed: ObservedLiveBeat(live)) != nil
        else { return }
        captureDraft = ""
        showCapture = false
    }

    public func persistRecall() {
        guard world.live?.phase == .recall else { return }
        guard world.live?.recallText != recallDraft else { return }
        guard let live = world.live else { return }
        apply(.setRecallText(recallDraft), observed: ObservedLiveBeat(live))
    }

    public func dismissCloseBeat() {
        guard let live = world.live, live.phase == .closeBeat, !live.isPaused else { return }
        let completedSessionID = live.id
        guard
            let commit = apply(
                .skip,
                observed: ObservedLiveBeat(live),
                warningPresentation: .syncMetadata
            ),
            commit.completedSession?.id == completedSessionID,
            let nextStep = commit.completedNextStep
        else { return }
        intentionDraft = nextStep
    }

    public func discardCapture() {
        captureDraft = ""
        showCapture = false
    }

    public func useLastIntention() {
        guard world.live == nil else { return }
        intentionDraft = world.profile.lastIntention
    }

    public func useNextStep() {
        guard world.live == nil,
            let nextStep = NextStepSuggestion.latest(in: world.history)
        else { return }
        intentionDraft = nextStep
    }

    @discardableResult
    public func useSessionResumption(
        _ session: CompletedSession,
        replacingCurrentDraft: Bool = false
    ) -> Bool {
        guard world.live == nil,
            let suggestion = SessionResumptionSuggestion.forSession(session)
        else { return false }
        guard
            replacingCurrentDraft
                || intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        intentionDraft = suggestion
        return true
    }

    public func beginParkedReview() {
        guard let live = world.live,
            live.phase == .recall,
            !live.isPaused,
            !live.captures.isEmpty,
            recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            live.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        showParkedReview = true
    }

    public func endParkedReview() {
        showParkedReview = false
    }

    @discardableResult
    public func useParkedThoughtAsNext(_ capture: CaptureItem) -> Bool {
        guard let live = world.live,
            live.phase == .recall,
            !live.isPaused,
            live.captures.contains(capture),
            recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            live.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        let nextStep = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextStep.isEmpty else { return false }
        guard
            apply(
                .useParkedThoughtAsNext(sessionID: live.id, capture: capture),
                observed: ObservedLiveBeat(live)
            ) != nil
        else {
            reloadAfterRejectedMutation()
            return false
        }
        showParkedReview = false
        return world.live?.recallText == nextStep
    }

    public func clearIntention() {
        intentionDraft = ""
    }

    public func setCuesEnabled(_ enabled: Bool) {
        apply(.setCuesEnabled(enabled))
    }

    public func retryStore() {
        do {
            var loaded = try store.load()
            if loaded.live?.isPaused == false {
                loaded = try store.update { engine in
                    engine.pauseUnpausedLiveOnProcessStart(now: Date())
                }.world
            }
            world = loaded
            now = Date()
            storeNeedsRecovery = false
            canPreserveAndReset = false
            activeIssue = nil
            sessionWasLive = loaded.live != nil
            refreshDraftsAfterChange()
            attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
            reloadGlance()
            cloudSync?.localWorldDidChange(takesOwnership: false)
        } catch {
            let code = FlowmoIssueClassifier.persistenceFailure(error)
            canPreserveAndReset = code == .storeUnreadable
            presentIssue(code, operation: .load, blocksStore: true)
        }
    }

    public func preserveAndResetStore() {
        guard storeNeedsRecovery, canPreserveAndReset else { return }
        do {
            _ = try store.quarantineInvalidWorldAndReset()
            world = try store.load()
            now = Date()
            storeNeedsRecovery = false
            canPreserveAndReset = false
            activeIssue = nil
            userNotice = "Original data was preserved and Flowmo was reset."
            intentionDraft = ""
            captureDraft = ""
            recallDraft = ""
            showCapture = false
            showParkedReview = false
            sessionWasLive = false
            attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
            reloadGlance()
        } catch {
            presentIssue(.preserveAndResetFailed, operation: .preserveAndReset)
        }
    }

    public func prepareFullDataExport() -> Data? {
        guard status.isIdle, !storeNeedsRecovery else { return nil }
        do {
            return try store.exportCurrentWorldJSON()
        } catch {
            presentIssue(.dataExportFailed, operation: .dataExport)
            return nil
        }
    }

    public func prepareDiagnosticExport() -> Data? {
        do {
            return try FlowmoDiagnosticReport(
                generatedAt: Date(),
                app: FlowmoDiagnosticReport.currentAppMetadata(),
                world: world,
                recentIssues: recentIssues,
                storeAvailable: !storeNeedsRecovery
            ).encoded()
        } catch {
            presentIssue(.diagnosticExportFailed, operation: .diagnosticExport)
            return nil
        }
    }

    public func deleteAllData() {
        guard status.isIdle, !storeNeedsRecovery else { return }
        do {
            _ = try store.deleteAllData()
            finishDataDeletion()
            finishCloudDataDeletion()
        } catch is StoreDataDeletionError {
            finishDataDeletion()
            presentIssue(.dataDeletionIncomplete, operation: .reset)
        } catch {
            presentIssue(.resetFailed, operation: .reset)
        }
    }

    private func finishCloudDataDeletion() {
        let metadata = try? syncMetadataStore.load()
        guard metadata?.containsPrivateCloudData != false else {
            try? syncMetadataStore.deleteOwnedData()
            userNotice = "All Flowmo data was deleted."
            return
        }
        guard let cloudSync else {
            preserveCloudDeletionIntent()
            presentIssue(.dataDeletionIncomplete, operation: .reset)
            return
        }
        userNotice = "Local Flowmo data was deleted. Removing iCloud data…"
        cloudSync.deleteAllData { [weak self] complete in
            guard let self else { return }
            if complete {
                self.userNotice = "All Flowmo data was deleted."
            } else {
                self.presentIssue(.dataDeletionIncomplete, operation: .reset)
            }
        }
    }

    private func preserveCloudDeletionIntent() {
        do {
            _ = try syncMetadataStore.update { metadata in
                metadata.prepareDataDeletion()
            }
        } catch {
            try? syncMetadataStore.deleteOwnedData()
            var replacement = WorldSyncMetadata()
            replacement.prepareDataDeletion()
            try? syncMetadataStore.save(replacement)
        }
    }

    public func exportFinished(kind: String, succeeded: Bool) {
        if succeeded {
            userNotice = kind == "diagnostics" ? "Diagnostic report exported." : "Flowmo data exported."
        } else {
            let code: FlowmoIssueCode = kind == "diagnostics" ? .diagnosticExportFailed : .dataExportFailed
            let operation: FlowmoDiagnosticOperation = kind == "diagnostics" ? .diagnosticExport : .dataExport
            presentIssue(code, operation: operation)
        }
    }

    public func clearNotice() {
        userNotice = nil
    }

    private func tick() {
        now = Date()
        var probe = Engine(world: world)
        let before = probe.world.live?.phase
        probe.sync(now: now)
        if probe.world != world {
            persistSync(cueFrom: before)
        }
    }

    private func persistSync(cueFrom before: SessionPhase?) {
        applying = true
        defer { applying = false }
        do {
            let engine = try store.update { engine in
                engine.sync(now: Date())
            }
            world = engine.world
            now = Date()
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
            reloadGlance()
            cloudSync?.localWorldDidChange(takesOwnership: false)
        } catch {
            handlePersistenceFailure(error, operation: .sync)
        }
    }

    private enum AuthorityWarningPresentation {
        case persistence
        case syncMetadata
    }

    @discardableResult
    private func apply(
        _ event: Event,
        observed: ObservedLiveBeat? = nil,
        warningPresentation: AuthorityWarningPresentation = .persistence
    ) -> WorldCommit? {
        guard syncStatus.conflict == nil else { return nil }
        let before = world.live?.phase
        applying = true
        defer { applying = false }
        let timestamp = Date()
        do {
            let result: WorldApplyResult
            if let observed {
                result = try worldAuthority.apply(event, observed: observed, at: timestamp)
            } else {
                result = try worldAuthority.apply(event, at: timestamp)
            }
            world = result.world
            now = timestamp
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
            reloadGlance()
            guard case .committed(let commit) = result else { return nil }
            cloudSync?.localWorldDidChange()
            if commit.warnings.contains(.auxiliaryPersistenceFailed) {
                switch warningPresentation {
                case .persistence:
                    presentIssue(.persistenceFailed, operation: .update)
                case .syncMetadata:
                    presentIssue(.syncMetadataUnavailable, operation: .sync)
                }
            }
            return commit
        } catch is EngineError {
            return nil
        } catch {
            if let persisted = try? store.load() {
                world = persisted
                now = timestamp
                attention.phaseChanged(
                    from: before,
                    to: world.live?.phase,
                    cuesEnabled: world.config.cuesEnabled
                )
                attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
                refreshDraftsAfterChange()
                reloadGlance()
            }
            handlePersistenceFailure(error, operation: .update)
            return nil
        }
    }

    private func reloadAfterRejectedMutation() {
        do {
            let before = world.live?.phase
            world = try store.load()
            now = Date()
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
            reloadGlance()
            cloudSync?.localWorldDidChange(takesOwnership: false)
        } catch {
            handlePersistenceFailure(error, operation: .load)
        }
    }

    public func resolveSyncConflict(
        _ conflict: WorldSyncConflict,
        choosing choice: WorldSyncChoice
    ) {
        cloudSync?.resolveConflict(conflict, choosing: choice)
    }

    private func startCloudSync() {
        guard cloudSync == nil else { return }
        guard
            let sync = CloudWorldSync.makeDefault(
                store: store,
                status: syncStatus,
                onWorldChange: { [weak self] syncedWorld in
                    guard let self else { return }
                    world = syncedWorld
                    now = Date()
                    refreshDraftsAfterChange()
                    attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
                    reloadGlance()
                }
            )
        else {
            return
        }
        cloudSync = sync
        sync.start()
    }

    private func refreshDraftsAfterChange() {
        if world.live?.phase == .recall {
            let stored = world.live?.recallText ?? ""
            if recallDraft != stored {
                recallDraft = stored
            }
        }
        let isLive = world.live != nil
        if !isLive {
            if sessionWasLive {
                intentionDraft = ""
            }
            showCapture = false
            showParkedReview = false
            captureDraft = ""
            recallDraft = ""
        } else {
            if world.live?.phase != .focus {
                showCapture = false
                captureDraft = ""
            }
            if world.live?.phase != .recall {
                recallDraft = ""
                showParkedReview = false
            } else if world.live?.isPaused == true || !recallDraft.isEmpty {
                showParkedReview = false
            }
        }
        sessionWasLive = isLive
    }

    private func reloadGlance() {
        Self.reloadGlanceTimeline()
    }

    private func finishDataDeletion() {
        world = .empty
        now = Date()
        intentionDraft = ""
        captureDraft = ""
        recallDraft = ""
        showCapture = false
        showParkedReview = false
        sessionWasLive = false
        attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
        reloadGlance()
    }

    private func handlePersistenceFailure(_ error: Error, operation: FlowmoDiagnosticOperation) {
        let code = FlowmoIssueClassifier.persistenceFailure(error)
        presentIssue(code, operation: operation, blocksStore: code == .storeUnreadable)
    }

    private func presentIssue(
        _ code: FlowmoIssueCode,
        operation: FlowmoDiagnosticOperation,
        blocksStore: Bool = false
    ) {
        let timestamp = Date()
        if blocksStore {
            storeNeedsRecovery = true
            // Once the store is blocked, the last in-memory phase is untrustworthy.
            // Reconcile against idle so no timed notification survives into recovery.
            attention.reconcile(
                status: Engine.sessionStatus(.empty, now: timestamp),
                cuesEnabled: false
            )
        }
        guard timestamp.timeIntervalSince(lastIssuePresentedAt[code] ?? .distantPast) >= 60 else { return }
        lastIssuePresentedAt[code] = timestamp
        FlowmoDiagnosticLog.emit(code, operation: operation)
        recentIssues.append(FlowmoIssueRecord(code: code, operation: operation, occurredAt: timestamp))
        recentIssues = Array(recentIssues.suffix(20))
        if !blocksStore {
            activeIssue = FlowmoPresentedIssue(code: code)
        }
    }

    private static func reloadGlanceTimeline() {
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: GlanceKind.id)
        #endif
    }

    public static func containerStore() throws -> Store {
        guard let group = Store.phoneSharedRoot() else {
            throw PhoneStoreConfigurationError.missingSharedAppGroup
        }

        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let legacyRoot = support.appendingPathComponent("flowmo", isDirectory: true)
            do {
                let didMigrate = try Store.migrateWorld(from: legacyRoot, to: group)
                if didMigrate {
                    reloadGlanceTimeline()
                }
            } catch {
                let sharedStore = Store(root: group)
                if FileManager.default.fileExists(atPath: sharedStore.worldURL.path) {
                    return sharedStore
                }
                throw error
            }
        }

        return Store(root: group)
    }
}
