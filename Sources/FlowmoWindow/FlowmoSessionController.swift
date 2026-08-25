import AppKit
import Combine
import FlowmoCore
import FlowmoSync
import Foundation

/// Window presentation. Both modes are fixed-size; the window never
/// resizes freely, because every pane is laid out against these bounds.
public enum DisplayMode: String, CaseIterable {
    case classic
    case mini

    public var windowContentSize: CGSize {
        switch self {
        case .classic: CGSize(width: 320, height: 460)
        case .mini: CGSize(width: 168, height: 176)
        }
    }
}

@MainActor
public final class FlowmoSessionController: ObservableObject {
    @Published public private(set) var world: World
    @Published public var now: Date = Date()
    @Published public var intentionDraft: String
    @Published public var captureDraft: String = ""
    @Published public var recallDraft: String = ""
    @Published public var showCapture: Bool = false
    @Published public var showParkedReview: Bool = false
    @Published public var isPinned: Bool = false
    @Published public var showGuardConfig: Bool = false
    @Published public private(set) var displayMode: DisplayMode
    @Published public private(set) var storeNeedsRecovery = false
    @Published public private(set) var lifecycleNeedsRecovery = false
    @Published public var activeIssue: FlowmoPresentedIssue?
    @Published public private(set) var userNotice: String?
    @Published public private(set) var recentIssues: [FlowmoIssueRecord] = []
    public let syncStatus: WorldSyncStatus

    let store: Store
    let attention: AttentionAdapter
    let focusGuard: FocusGuardAdapter
    private let evidence: LocalEvidenceRecorder
    private let macRecovery: MacProcessRecoveryMarker
    private let syncMetadataStore: WorldSyncMetadataStore
    private var cloudSync: CloudWorldSync?

    private var timer: Timer?
    private var watcher: WorldWatcher?
    private var applying = false
    private var sessionWasLive = false
    private var didClaimMacProcessLifetime = false
    private var markerRecoveryFailed = false
    private var pauseRecoveryFailed = false
    private var dataDeletionWarningPending = false
    private var pendingRecoveryPause: RecoveryPauseRequest?
    private var lastIssuePresentedAt: [FlowmoIssueCode: Date] = [:]
    private var cancellables = Set<AnyCancellable>()

    private struct RecoveryPauseRequest {
        let sessionID: UUID
        let requestedAt: Date
    }

    public var status: SessionStatus {
        Engine.sessionStatus(world, now: now)
    }

    public var effectiveWindowContentSize: CGSize {
        Self.windowContentSize(
            displayMode: displayMode,
            storeNeedsRecovery: storeNeedsRecovery,
            lifecycleNeedsRecovery: lifecycleNeedsRecovery
        )
    }

    static func windowContentSize(
        displayMode: DisplayMode,
        storeNeedsRecovery: Bool,
        lifecycleNeedsRecovery: Bool
    ) -> CGSize {
        storeNeedsRecovery || lifecycleNeedsRecovery
            ? DisplayMode.classic.windowContentSize
            : displayMode.windowContentSize
    }

    public var guardStatusLine: String? {
        if focusGuard.runtime.degraded {
            return "Guard unavailable"
        }
        return FocusGuard.statusLine(world: world)
    }

    public init(
        store: Store = .default,
        attention: AttentionAdapter = AttentionAdapter(),
        focusGuard: FocusGuardAdapter = FocusGuardAdapter()
    ) {
        self.store = store
        self.attention = attention
        self.focusGuard = focusGuard
        self.evidence = LocalEvidenceRecorder(root: store.root)
        self.macRecovery = MacProcessRecoveryMarker(store: store)
        self.syncMetadataStore = WorldSyncMetadataStore(root: store.root)
        self.syncStatus = WorldSyncStatus()

        let loaded: World
        do {
            loaded = try store.load()
        } catch {
            let timestamp = Date()
            loaded = .empty
            self.storeNeedsRecovery = true
            self.recentIssues = [
                FlowmoIssueRecord(code: .storeUnreadable, operation: .load, occurredAt: timestamp)
            ]
            self.lastIssuePresentedAt[.storeUnreadable] = timestamp
            FlowmoDiagnosticLog.emit(.storeUnreadable, operation: .load)
        }
        self.world = loaded
        self.intentionDraft = ""
        self.sessionWasLive = loaded.live != nil
        self.displayMode =
            DisplayMode(
                rawValue: UserDefaults.standard.string(forKey: "FlowmoDisplayMode") ?? ""
            ) ?? .classic
        if loaded.live?.phase == .recall {
            self.recallDraft = loaded.live?.recallText ?? ""
        }
        focusGuard.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        syncStatus.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public func setDisplayMode(_ mode: DisplayMode) {
        guard mode != displayMode else { return }
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "FlowmoDisplayMode")
    }

    public func startRunning() {
        startCloudSync()
        focusGuard.attach(
            bringForward: { [weak self] in
                self?.attention.window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
            },
            observeEvidence: { [evidence = self.evidence] event in
                evidence.record(event)
            }
        )
        if !storeNeedsRecovery {
            beginMacProcessLifetime()
        }

        reloadFromStore(cueIfChanged: false)
        reconcileGuard()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        watcher = WorldWatcher(url: store.worldURL) { [weak self] in
            Task { @MainActor in
                self?.reloadFromStore(cueIfChanged: true)
            }
        }
    }

    public func start() {
        apply(.start(intention: intentionDraft))
    }

    public func skip() {
        apply(.skip)
    }

    public func stopFocus() {
        apply(.stopFocus)
    }

    public func continueSession() {
        apply(.`continue`)
    }

    public func restartSession() {
        apply(.restart)
    }

    @discardableResult
    public func pauseForRecovery() -> Bool {
        guard let live = world.live, !live.isPaused else { return true }
        guard !syncMetadataStore.isRemoteLiveSession(live.id) else { return true }
        if pendingRecoveryPause?.sessionID != live.id {
            pendingRecoveryPause = RecoveryPauseRequest(sessionID: live.id, requestedAt: Date())
        }
        return persistPendingRecoveryPause()
    }

    public func prepareForTermination() {
        guard macRecovery.ownsLifecycle else { return }
        let timestamp = Date()
        do {
            let engine = try store.update(
                { engine in
                    if let live = engine.world.live,
                        !live.isPaused,
                        !self.syncMetadataStore.isRemoteLiveSession(live.id)
                    {
                        let pauseAt = max(timestamp, live.phaseStartedAt)
                        try engine.apply(.pauseForRecovery, now: pauseAt)
                    }
                },
                afterPersist: { _ in
                    try self.macRecovery.finishNormally()
                }
            )
            world = engine.world
            now = timestamp
        } catch let error as MacProcessRecoveryError {
            handleMarkerRecoveryFailure(error, operation: .recoveryFinish)
        } catch {
            handlePauseRecoveryFailure(error)
        }
    }

    public func submitCapture() {
        let trimmed = captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard apply(.capture(trimmed)) else { return }
        captureDraft = ""
        showCapture = false
    }

    public func persistRecall() {
        guard world.live?.phase == .recall else { return }
        guard world.live?.recallText != recallDraft else { return }
        apply(.setRecallText(recallDraft))
    }

    public func dismissCloseBeat() {
        guard world.live?.phase == .closeBeat, world.live?.isPaused != true else { return }
        apply(.skip)
    }

    public func configureFocusGuard(_ config: FocusGuardConfiguration) {
        apply(.configureFocusGuard(config))
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
    public func resumeCompletedSession(
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
            live.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !live.captures.isEmpty
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
            live.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard apply(.useParkedThoughtAsNext(sessionID: live.id, capture: capture)) else {
            reloadFromStore(cueIfChanged: false)
            return false
        }
        showParkedReview = false
        return world.live?.recallText == text
    }

    public func clearIntention() {
        intentionDraft = ""
    }

    public func setCuesEnabled(_ enabled: Bool) {
        apply(.setCuesEnabled(enabled))
    }

    public func addGuardedApp(bundleIdentifier: String) {
        var config = world.config.focusGuard
        config.bundleIdentifiers.append(bundleIdentifier)
        config.enabled = true
        apply(.configureFocusGuard(config))
    }

    public func removeGuardedApp(bundleIdentifier: String) {
        var config = world.config.focusGuard
        config.bundleIdentifiers.removeAll { $0 == bundleIdentifier }
        apply(.configureFocusGuard(config))
    }

    public func setGuardEnabled(_ enabled: Bool) {
        var config = world.config.focusGuard
        config.enabled = enabled
        apply(.configureFocusGuard(config))
    }

    public func stayFocused() {
        focusGuard.stayFocused()
    }

    public func openOnce() {
        focusGuard.openOnce()
    }

    public func retryStore() {
        let needsLifecycleClaim = !didClaimMacProcessLifetime
        reloadFromStore(cueIfChanged: false)
        if !storeNeedsRecovery, needsLifecycleClaim {
            beginMacProcessLifetime()
        }
    }

    public func retryLifecycleRecovery() {
        if pendingRecoveryPause != nil {
            _ = persistPendingRecoveryPause()
        }
        guard markerRecoveryFailed else {
            updateLifecycleRecoveryState()
            return
        }
        if didClaimMacProcessLifetime, macRecovery.ownsLifecycle {
            let timestamp = Date()
            do {
                _ = try store.update { engine in
                    try macRecovery.refreshOwnership(
                        for: markerSessionID(engine.world.live?.id),
                        at: timestamp
                    )
                }
                markerRecoveryFailed = false
                clearRecoveryIssueIfResolved()
            } catch let error as MacProcessRecoveryError {
                handleMarkerRecoveryFailure(error, operation: .recoveryClaim)
            } catch {
                handlePersistenceFailure(error, operation: .recoveryClaim)
            }
        } else {
            didClaimMacProcessLifetime = false
            beginMacProcessLifetime()
        }
        updateLifecycleRecoveryState()
    }

    public func preserveAndResetStore() {
        guard storeNeedsRecovery else { return }
        do {
            _ = try store.quarantineInvalidWorldAndReset()
            world = try store.load()
            now = Date()
            storeNeedsRecovery = false
            activeIssue = nil
            userNotice = "Original data was preserved and Flowmo was reset."
            intentionDraft = ""
            captureDraft = ""
            recallDraft = ""
            showCapture = false
            showParkedReview = false
            sessionWasLive = false
            beginMacProcessLifetime()
            reconcileGuard()
        } catch {
            presentIssue(.preserveAndResetFailed, operation: .preserveAndReset)
        }
    }

    public func prepareFullDataExport() -> Data? {
        guard status.isIdle, !storeNeedsRecovery, !lifecycleNeedsRecovery else { return nil }
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

    public func prepareEvidenceExport() -> Data? {
        guard status.isIdle, !storeNeedsRecovery, !lifecycleNeedsRecovery else { return nil }
        do {
            return try evidence.export(generatedAt: Date())
        } catch {
            presentIssue(.evidenceExportFailed, operation: .evidenceExport)
            return nil
        }
    }

    public func deleteAllData() {
        guard status.isIdle, !storeNeedsRecovery, !lifecycleNeedsRecovery else { return }
        userNotice = nil
        var deletionIncomplete = false
        // Idle makes new Guard observations ineligible while this barrier and
        // the following deletion run, so no queued write can recreate the file.
        evidence.flush()
        do {
            _ = try store.deleteAllData()
        } catch is StoreDataDeletionError {
            deletionIncomplete = true
        } catch {
            presentIssue(.resetFailed, operation: .reset)
            return
        }

        let timestamp = Date()
        do {
            let engine = try store.update { engine in
                try macRecovery.recordDataDeletion(engine.world.live?.id, at: timestamp)
            }
            finishDataDeletion(world: engine.world)
            if deletionIncomplete {
                markDataDeletionIncomplete()
            } else {
                finishCloudDataDeletion()
            }
        } catch is MacProcessRecoveryDataDeletionError {
            finishDataDeletion(world: (try? store.load()) ?? .empty)
            markDataDeletionIncomplete()
        } catch let error as MacProcessRecoveryError {
            finishDataDeletion(world: (try? store.load()) ?? .empty)
            markDataDeletionIncomplete()
            handleMarkerRecoveryFailure(error, operation: .recoveryHeartbeat)
        } catch {
            finishDataDeletion(world: (try? store.load()) ?? .empty)
            markDataDeletionIncomplete()
            handlePersistenceFailure(error, operation: .reset)
        }
    }

    private func finishCloudDataDeletion() {
        let metadata = try? syncMetadataStore.load()
        guard metadata?.containsPrivateCloudData != false else {
            try? syncMetadataStore.deleteOwnedData()
            clearDataDeletionWarning()
            userNotice = "All Flowmo data was deleted."
            return
        }
        guard let cloudSync else {
            preserveCloudDeletionIntent()
            markDataDeletionIncomplete()
            return
        }
        userNotice = "Local Flowmo data was deleted. Removing iCloud data…"
        cloudSync.deleteAllData { [weak self] complete in
            guard let self else { return }
            if complete {
                self.clearDataDeletionWarning()
                self.userNotice = "All Flowmo data was deleted."
            } else {
                self.markDataDeletionIncomplete()
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

    public func exportFinished(kind: FlowmoExportKind, succeeded: Bool) {
        if succeeded {
            userNotice = kind.successMessage
        } else {
            presentIssue(kind.failureCode, operation: kind.diagnosticOperation)
        }
    }

    public func clearNotice() {
        userNotice = nil
    }

    /// Claims the Mac process marker and recovers only a session owned by a
    /// dead Mac host. This runs before the already-wired window is shown.
    func beginMacProcessLifetime() {
        guard !didClaimMacProcessLifetime else { return }
        applying = true
        defer { applying = false }
        let timestamp = Date()
        do {
            var preparation = MacProcessRecoveryMarker.ClaimPreparation.contended
            let engine = try store.update { engine in
                preparation = try macRecovery.prepareClaim(
                    &engine,
                    now: timestamp,
                    trackLiveSession: !syncMetadataStore.isRemoteLiveSession(engine.world.live?.id)
                )
            }
            switch preparation {
            case .prepared:
                macRecovery.commitPreparedClaim()
            case .contended:
                world = engine.world
                now = timestamp
                didClaimMacProcessLifetime = false
                handleMarkerRecoveryFailure(
                    MacProcessRecoveryError.claimContended,
                    operation: .recoveryClaim
                )
                refreshDraftsAfterChange()
                return
            }
            world = engine.world
            now = timestamp
            didClaimMacProcessLifetime = true
            markerRecoveryFailed = false
            clearRecoveryIssueIfResolved()
            refreshDraftsAfterChange()
            reconcileGuard()
        } catch let error as MacProcessRecoveryError {
            handleMarkerRecoveryFailure(error, operation: .recoveryClaim)
        } catch {
            if FlowmoIssueClassifier.persistenceFailure(error) == .storeUnreadable {
                handlePersistenceFailure(error, operation: .recoveryClaim)
            } else {
                handleMarkerRecoveryFailure(error, operation: .recoveryClaim)
            }
        }
    }

    private func tick() {
        now = Date()
        if pendingRecoveryPause != nil {
            _ = persistPendingRecoveryPause()
            return
        }
        guard !storeNeedsRecovery, !lifecycleNeedsRecovery else { return }
        var probe = Engine(world: world)
        let before = probe.world.live?.phase
        probe.sync(now: now)
        if probe.world != world {
            persistSync(cueFrom: before)
        } else if world.live?.isPaused == false, macRecovery.needsHeartbeat(at: now) {
            persistHeartbeat(at: now)
        }
    }

    private func persistSync(cueFrom before: SessionPhase?) {
        applying = true
        defer { applying = false }
        let timestamp = Date()
        do {
            let engine = try store.update { engine in
                engine.sync(now: timestamp)
                try macRecovery.recordObservation(markerSessionID(engine.world.live?.id), at: timestamp)
            }
            world = engine.world
            now = timestamp
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
            reconcileGuard()
            cloudSync?.localWorldDidChange(takesOwnership: false)
        } catch let error as MacProcessRecoveryError {
            handleMarkerRecoveryFailure(error, operation: .recoveryHeartbeat)
        } catch {
            handlePersistenceFailure(error, operation: .sync)
        }
    }

    private func persistHeartbeat(at timestamp: Date) {
        applying = true
        defer { applying = false }
        do {
            _ = try store.update { engine in
                try macRecovery.recordObservation(markerSessionID(engine.world.live?.id), at: timestamp)
            }
        } catch let error as MacProcessRecoveryError {
            handleMarkerRecoveryFailure(error, operation: .recoveryHeartbeat)
        } catch {
            handlePersistenceFailure(error, operation: .heartbeat)
        }
    }

    @discardableResult
    private func apply(_ event: Event) -> Bool {
        guard !storeNeedsRecovery, !lifecycleNeedsRecovery else { return false }
        guard syncStatus.conflict == nil else { return false }
        let before = world.live?.phase
        applying = true
        defer { applying = false }
        let timestamp = Date()
        let wasRemote = syncMetadataStore.isRemoteLiveSession(world.live?.id)
        do {
            let engine = try store.update(
                { engine in
                    try engine.apply(event, now: timestamp)
                    if let sessionID = engine.world.live?.id {
                        try macRecovery.recordObservation(wasRemote ? nil : sessionID, at: timestamp)
                    }
                },
                afterPersist: { engine in
                    try? self.syncMetadataStore.markLocalControl()
                    if engine.world.live == nil {
                        try self.macRecovery.recordObservation(nil, at: timestamp)
                    } else if wasRemote {
                        try self.macRecovery.recordObservation(engine.world.live?.id, at: timestamp)
                    }
                }
            )
            world = engine.world
            now = timestamp
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
            reconcileGuard()
            cloudSync?.localWorldDidChange()
            return true
        } catch is EngineError {
            // Expected state race: another local surface won. Reload will reconcile.
            return false
        } catch let error as MacProcessRecoveryError {
            handleMarkerRecoveryFailure(error, operation: .recoveryHeartbeat)
            return false
        } catch {
            handlePersistenceFailure(error, operation: .update)
            return false
        }
    }

    private func reloadFromStore(cueIfChanged: Bool) {
        if applying { return }
        do {
            let loaded = try store.load()
            let timestamp = Date()
            var engine = Engine(world: loaded)
            let before = world.live?.phase
            engine.sync(now: timestamp)
            if engine.world != loaded
                || macRecovery.needsObservation(for: markerSessionID(engine.world.live?.id))
            {
                applying = true
                defer { applying = false }
                engine = try store.update { engine in
                    engine.sync(now: timestamp)
                    try macRecovery.recordObservation(markerSessionID(engine.world.live?.id), at: timestamp)
                }
            }
            let changed = engine.world != world
            world = engine.world
            now = timestamp
            storeNeedsRecovery = false
            if activeIssue?.code == .storeUnreadable {
                activeIssue = nil
            }
            if cueIfChanged, changed {
                attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            }
            refreshDraftsAfterChange()
            reconcileGuard()
            if changed {
                cloudSync?.localWorldDidChange()
            }
            if !didClaimMacProcessLifetime {
                beginMacProcessLifetime()
            }
        } catch let error as MacProcessRecoveryError {
            handleMarkerRecoveryFailure(error, operation: .recoveryHeartbeat)
        } catch {
            handlePersistenceFailure(error, operation: .load)
        }
    }

    public func resolveSyncConflict(choosing choice: WorldSyncChoice) {
        cloudSync?.resolveConflict(choosing: choice)
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
                    reconcileGuard()
                }
            )
        else {
            return
        }
        cloudSync = sync
        sync.start()
    }

    private func markerSessionID(_ id: UUID?) -> UUID? {
        syncMetadataStore.isRemoteLiveSession(id) ? nil : id
    }

    @discardableResult
    private func persistPendingRecoveryPause() -> Bool {
        guard let request = pendingRecoveryPause else { return true }
        applying = true
        defer { applying = false }
        do {
            var requestStillMatches = false
            let engine = try store.update { engine in
                guard let live = engine.world.live, live.id == request.sessionID else { return }
                requestStillMatches = true
                guard !live.isPaused else { return }
                let pauseAt = max(request.requestedAt, live.phaseStartedAt)
                try engine.apply(.pauseForRecovery, now: pauseAt)
            }
            world = engine.world
            now = request.requestedAt
            if !requestStillMatches || engine.world.live?.isPaused == true {
                pendingRecoveryPause = nil
                pauseRecoveryFailed = false
                clearRecoveryIssueIfResolved()
            }
            refreshDraftsAfterChange()
            reconcileGuard()
            if pendingRecoveryPause == nil {
                cloudSync?.localWorldDidChange()
            }
            return pendingRecoveryPause == nil
        } catch {
            handlePauseRecoveryFailure(error)
            return false
        }
    }

    private func refreshDraftsAfterChange() {
        let phase = world.live?.phase
        if phase == .recall {
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
            showGuardConfig = false
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

    private func reconcileGuard() {
        focusGuard.reconcile(world: world)
    }

    private func finishDataDeletion(world nextWorld: World = .empty) {
        world = nextWorld
        now = Date()
        intentionDraft = ""
        captureDraft = ""
        recallDraft = ""
        showCapture = false
        showParkedReview = false
        showGuardConfig = false
        if nextWorld.live?.phase == .recall {
            recallDraft = nextWorld.live?.recallText ?? ""
        }
        sessionWasLive = nextWorld.live != nil
        reconcileGuard()
    }

    private func handlePersistenceFailure(_ error: Error, operation: FlowmoDiagnosticOperation) {
        let code = FlowmoIssueClassifier.persistenceFailure(error)
        presentIssue(code, operation: operation, blocksStore: code == .storeUnreadable)
    }

    private func handleMarkerRecoveryFailure(_ error: Error, operation: FlowmoDiagnosticOperation) {
        markerRecoveryFailed = true
        updateLifecycleRecoveryState()
        presentIssue(.recoveryUnavailable, operation: operation)
    }

    private func handlePauseRecoveryFailure(_ error: Error) {
        let persistenceCode = FlowmoIssueClassifier.persistenceFailure(error)
        if persistenceCode == .storeUnreadable {
            handlePersistenceFailure(error, operation: .recoveryPause)
            return
        }
        pauseRecoveryFailed = true
        updateLifecycleRecoveryState()
        presentIssue(.recoveryUnavailable, operation: .recoveryPause)
    }

    private func updateLifecycleRecoveryState() {
        lifecycleNeedsRecovery = markerRecoveryFailed || pauseRecoveryFailed
        if lifecycleNeedsRecovery {
            focusGuard.reconcile(world: .empty)
        }
    }

    private func clearRecoveryIssueIfResolved() {
        updateLifecycleRecoveryState()
        guard !lifecycleNeedsRecovery else { return }
        if activeIssue?.code == .recoveryUnavailable {
            activeIssue =
                dataDeletionWarningPending
                ? FlowmoPresentedIssue(code: .dataDeletionIncomplete)
                : nil
        } else if activeIssue == nil, dataDeletionWarningPending {
            activeIssue = FlowmoPresentedIssue(code: .dataDeletionIncomplete)
        }
        reconcileGuard()
    }

    private func markDataDeletionIncomplete() {
        dataDeletionWarningPending = true
        userNotice = nil
        presentIssue(.dataDeletionIncomplete, operation: .reset)
        // A preceding attempt may have rate-limited this diagnostic code. The
        // user-visible privacy warning must still survive lifecycle recovery.
        activeIssue = FlowmoPresentedIssue(code: .dataDeletionIncomplete)
    }

    private func clearDataDeletionWarning() {
        dataDeletionWarningPending = false
        if activeIssue?.code == .dataDeletionIncomplete {
            activeIssue = nil
        }
    }

    private func presentIssue(
        _ code: FlowmoIssueCode,
        operation: FlowmoDiagnosticOperation,
        blocksStore: Bool = false
    ) {
        let timestamp = Date()
        if blocksStore {
            storeNeedsRecovery = true
            focusGuard.reconcile(world: .empty)
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
}
