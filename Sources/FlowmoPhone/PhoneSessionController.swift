import Combine
import Foundation
import FlowmoCore

@MainActor
public final class PhoneSessionController: ObservableObject {
    @Published public private(set) var world: World
    @Published public var now: Date = Date()
    @Published public var intentionDraft: String
    @Published public var captureDraft: String = ""
    @Published public var recallDraft: String = ""
    @Published public var showCapture: Bool = false

    let store: Store
    let attention: PhoneAttention

    private var timer: Timer?
    private var applying = false

    public var status: SessionStatus {
        Engine.sessionStatus(world, now: now)
    }

    public init(store: Store, attention: PhoneAttention = PhoneAttention()) {
        self.store = store
        self.attention = attention
        var loaded = (try? store.load()) ?? .empty
        if loaded.live?.isPaused == false {
            do {
                loaded = try store.update { engine in
                    engine.pauseUnpausedLiveOnProcessStart(now: Date())
                }.world
            } catch {
                loaded = (try? store.load()) ?? loaded
            }
        }
        self.world = loaded
        self.intentionDraft = loaded.profile.lastIntention
        if loaded.live?.phase == .recall {
            self.recallDraft = loaded.live?.recallText ?? ""
        }
        attention.reconcile(status: Engine.sessionStatus(loaded, now: Date()), cuesEnabled: loaded.config.cuesEnabled)
    }

    public func startRunning() {
        attention.requestPermission()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func start() { apply(.start(intention: intentionDraft)) }
    public func skip() { apply(.skip) }
    public func stopFocus() { apply(.stopFocus) }
    public func continueSession() { apply(.`continue`) }

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

    public func setCuesEnabled(_ enabled: Bool) {
        apply(.setCuesEnabled(enabled))
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
            attention.phaseChanged(from: before, to: world.live?.phase, cuesEnabled: world.config.cuesEnabled)
            attention.reconcile(status: status, cuesEnabled: world.config.cuesEnabled)
            refreshDraftsAfterChange()
        } catch {
        }
    }

    private func refreshDraftsAfterChange() {
        if world.live?.phase == .recall {
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

    public static func containerStore() -> Store {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return Store(root: root.appendingPathComponent("flowmo", isDirectory: true))
    }
}
