import AppKit
import Combine
import Foundation
import FlowmoCore

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
    @Published public var isPinned: Bool = false
    @Published public var showGuardConfig: Bool = false
    @Published public private(set) var displayMode: DisplayMode

    let store: Store
    let attention: AttentionAdapter
    let focusGuard: FocusGuardAdapter
    private let macRecovery: MacProcessRecoveryMarker

    private var timer: Timer?
    private var watcher: WorldWatcher?
    private var applying = false
    private var cancellables = Set<AnyCancellable>()

    public var status: SessionStatus {
        Engine.sessionStatus(world, now: now)
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
        self.macRecovery = MacProcessRecoveryMarker(store: store)

        let loaded = (try? store.load()) ?? .empty
        self.world = loaded
        self.intentionDraft = loaded.profile.lastIntention
        self.displayMode = DisplayMode(
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
    }

    public func setDisplayMode(_ mode: DisplayMode) {
        guard mode != displayMode else { return }
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "FlowmoDisplayMode")
    }

    public func startRunning() {
        focusGuard.attach { [weak self] in
            self?.attention.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        beginMacProcessLifetime()

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

    @discardableResult
    public func pauseForRecovery() -> Bool {
        apply(.pauseForRecovery)
    }

    public func prepareForTermination() {
        guard macRecovery.ownsLifecycle, pauseForRecovery() else { return }
        macRecovery.finishNormally()
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

    public func clearIntention() {
        intentionDraft = ""
        apply(.setLastIntention(""))
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

    /// Claims the Mac process marker and recovers only a session owned by a
    /// dead Mac host. This runs before the window is constructed.
    private func beginMacProcessLifetime() {
        applying = true
        defer { applying = false }
        let timestamp = Date()
        do {
            let engine = try store.update { engine in
                macRecovery.claim(&engine, now: timestamp)
            }
            world = engine.world
            now = timestamp
            refreshDraftsAfterChange()
            reconcileGuard()
        } catch {
            return
        }
    }

    private func tick() {
        now = Date()
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
                macRecovery.recordObservation(engine.world.live?.id, at: timestamp)
            }
            world = engine.world
            now = timestamp
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
            reconcileGuard()
        } catch {
            var engine = Engine(world: world)
            engine.sync(now: timestamp)
            world = engine.world
        }
    }

    private func persistHeartbeat(at timestamp: Date) {
        applying = true
        defer { applying = false }
        do {
            _ = try store.update { engine in
                macRecovery.recordObservation(engine.world.live?.id, at: timestamp)
            }
        } catch {
            return
        }
    }

    @discardableResult
    private func apply(_ event: Event) -> Bool {
        let before = world.live?.phase
        applying = true
        defer { applying = false }
        let timestamp = Date()
        do {
            let engine = try store.update { engine in
                try engine.apply(event, now: timestamp)
                macRecovery.recordObservation(engine.world.live?.id, at: timestamp)
            }
            world = engine.world
            now = timestamp
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
            reconcileGuard()
            return true
        } catch {
            // Invalid for the current phase; leave the window as-is.
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
            if engine.world != loaded || macRecovery.needsObservation(for: engine.world.live?.id) {
                applying = true
                defer { applying = false }
                engine = try store.update { engine in
                    engine.sync(now: timestamp)
                    macRecovery.recordObservation(engine.world.live?.id, at: timestamp)
                }
            }
            let changed = engine.world != world
            world = engine.world
            now = timestamp
            if cueIfChanged, changed {
                attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            }
            refreshDraftsAfterChange()
            reconcileGuard()
        } catch {
            return
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
        if world.live == nil {
            intentionDraft = world.profile.lastIntention
            showCapture = false
            captureDraft = ""
            recallDraft = ""
        } else {
            showGuardConfig = false
        }
    }

    private func reconcileGuard() {
        focusGuard.reconcile(world: world)
    }
}
