import Combine
import Foundation
import FlowmoCore

@MainActor
public final class FlowmoSessionController: ObservableObject {
    @Published public private(set) var world: World
    @Published public var now: Date = Date()
    @Published public var intentionDraft: String
    @Published public var captureDraft: String = ""
    @Published public var recallDraft: String = ""
    @Published public var showCapture: Bool = false
    @Published public var isPinned: Bool = false

    let store: Store
    let attention: AttentionAdapter

    private var timer: Timer?
    private var watcher: WorldWatcher?
    private var applying = false

    public var status: SessionStatus {
        Engine.sessionStatus(world, now: now)
    }

    public init(store: Store = .default, attention: AttentionAdapter = AttentionAdapter()) {
        self.store = store
        self.attention = attention
        let loaded = (try? store.load()) ?? .empty
        self.world = loaded
        self.intentionDraft = loaded.profile.lastIntention
        if loaded.live?.phase == .recall {
            self.recallDraft = loaded.live?.recallText ?? ""
        }
    }

    public func startRunning() {
        reloadFromStore(cueIfChanged: false)
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

    public func pauseForRecovery() {
        apply(.pauseForRecovery)
    }

    public func submitCapture() {
        apply(.capture(captureDraft))
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
            attention.phaseChanged(from: before, to: world.live?.phase)
            refreshDraftsAfterChange()
        } catch {
            var engine = Engine(world: world)
            engine.sync(now: Date())
            world = engine.world
        }
    }

    private func apply(_ event: Event) {
        let before = world.live?.phase
        applying = true
        defer { applying = false }
        do {
            let engine = try store.update { engine in
                try engine.apply(event, now: Date())
            }
            world = engine.world
            now = Date()
            attention.phaseChanged(from: before, to: world.live?.phase)
            refreshDraftsAfterChange()
        } catch {
            // Invalid for the current phase; leave the window as-is.
        }
    }

    private func reloadFromStore(cueIfChanged: Bool) {
        if applying { return }
        do {
            let loaded = try store.load()
            var engine = Engine(world: loaded)
            let before = world.live?.phase
            engine.sync(now: Date())
            if engine.world != loaded {
                applying = true
                defer { applying = false }
                engine = try store.update { $0.sync(now: Date()) }
            }
            let changed = engine.world != world
            world = engine.world
            now = Date()
            if cueIfChanged, changed {
                attention.phaseChanged(from: before, to: world.live?.phase)
            }
            refreshDraftsAfterChange()
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
        }
    }
}
