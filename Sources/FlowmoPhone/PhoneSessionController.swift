import Combine
import Foundation
import FlowmoCore
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
        var didRecover = false
        if loaded.live?.isPaused == false {
            do {
                loaded = try store.update { engine in
                    engine.pauseUnpausedLiveOnProcessStart(now: Date())
                }.world
                didRecover = true
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

    public func submitCapture() {
        let trimmed = captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apply(.capture(trimmed))
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
        intentionDraft = ""
        apply(.setLastIntention(""))
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
            reloadGlance()
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
            reloadGlance()
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

    private func reloadGlance() {
        Self.reloadGlanceTimeline()
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
            let didMigrate = try Store.migrateWorld(from: legacyRoot, to: group)
            if didMigrate {
                reloadGlanceTimeline()
            }
        }

        return Store(root: group)
    }
}
