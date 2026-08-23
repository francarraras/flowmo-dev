import Combine
import FlowmoCore
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
    @Published public private(set) var storeNeedsRecovery = false
    @Published public private(set) var canPreserveAndReset = false
    @Published public var activeIssue: FlowmoPresentedIssue?
    @Published public private(set) var userNotice: String?
    @Published public private(set) var recentIssues: [FlowmoIssueRecord] = []

    let store: Store
    let attention: PhoneAttention

    private var timer: Timer?
    private var applying = false
    private var sessionWasLive = false
    private var lastIssuePresentedAt: [FlowmoIssueCode: Date] = [:]

    public var status: SessionStatus {
        Engine.sessionStatus(world, now: now)
    }

    public init(store: Store, attention: PhoneAttention = PhoneAttention()) {
        self.store = store
        self.attention = attention
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
        if startupIssue == nil, loaded.live?.isPaused == false {
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
        if didRecover {
            reloadGlance()
        }
    }

    public func startRunning() {
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
    }

    public func start() { apply(.start(intention: intentionDraft)) }
    public func skip() { apply(.skip) }
    public func stopFocus() { apply(.stopFocus) }
    public func continueSession() { apply(.`continue`) }
    public func restartSession() { apply(.restart) }

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

    public func discardCapture() {
        captureDraft = ""
        showCapture = false
    }

    public func clearIntention() {
        guard apply(.setLastIntention("")) else { return }
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
            userNotice = "All Flowmo data was deleted."
        } catch is StoreDataDeletionError {
            finishDataDeletion()
            presentIssue(.dataDeletionIncomplete, operation: .reset)
        } catch {
            presentIssue(.resetFailed, operation: .reset)
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
        } catch {
            handlePersistenceFailure(error, operation: .sync)
        }
    }

    @discardableResult
    private func apply(_ event: Event) -> Bool {
        let before = world.live?.phase
        applying = true
        defer { applying = false }
        do {
            let engine = try store.update { engine in
                try engine.apply(event, now: Date())
            }
            world = engine.world
            now = Date()
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
            reloadGlance()
            return true
        } catch is EngineError {
            return false
        } catch {
            handlePersistenceFailure(error, operation: .update)
            return false
        }
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
            captureDraft = ""
            recallDraft = ""
        } else {
            if world.live?.phase != .focus {
                showCapture = false
                captureDraft = ""
            }
            if world.live?.phase != .recall {
                recallDraft = ""
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
