import Foundation

public enum BreakMath {
    public static func earnedBreak(focus: TimeInterval, ratio: Double) -> TimeInterval {
        guard focus.isFinite, ratio.isFinite, ratio > 0 else { return 0 }
        let result = max(0, focus) / ratio
        return result.isFinite ? result : .greatestFiniteMagnitude
    }
}

public struct Engine: Equatable, Sendable {
    public var world: World

    public init(world: World = .empty) {
        self.world = world
    }

    public mutating func apply(_ event: Event, now: Date) throws {
        if world.live?.isPaused == true {
            switch event {
            case .pauseForRecovery, .`continue`, .restart, .setCuesEnabled:
                break
            default:
                throw EngineError.recoveryPaused
            }
        }

        switch event {
        case .pauseForRecovery:
            if world.live?.isPaused != true {
                sync(now: now)
            }
            pauseForRecovery(now: now)
            return
        case .`continue`:
            try continuePaused(now: now)
            return
        case .restart:
            try restart(now: now)
            return
        default:
            break
        }
        let phaseBeforeSync = world.live?.phase
        if world.live?.isPaused != true {
            sync(now: now)
        }
        // A skip targets the observed phase, never one entered by this catch-up.
        if case .skip = event, phaseBeforeSync != world.live?.phase {
            return
        }
        switch event {
        case .start(let intention):
            try start(intention: intention, now: now)
        case .skip:
            try skip(now: now)
        case .stopFocus:
            try stopFocus(now: now)
        case .capture(let text):
            try capture(text, now: now)
        case .setRecallText(let text):
            try setRecallText(text)
        case .cancel:
            try cancel()
        case .configureFocusGuard(let config):
            try configureFocusGuard(config)
        case .setCuesEnabled(let enabled):
            world.config.cuesEnabled = enabled
        case .setLastIntention(let text):
            try setLastIntention(text)
        case .pauseForRecovery, .`continue`, .restart:
            break
        }
    }

    /// Move timed phases forward if their clock has run out. Close beat never auto-idles.
    /// Frozen (paused) sessions do not advance.
    public mutating func sync(now: Date) {
        guard var live = world.live, !live.isPaused else { return }

        while true {
            switch live.phase {
            case .prime:
                let deadline = live.phaseStartedAt.addingTimeInterval(live.primeDuration)
                guard now >= deadline else {
                    world.live = live
                    return
                }
                enterFocus(&live, now: deadline)
            case .onBreak:
                guard let start = live.breakStartedAt, let duration = live.breakDuration else {
                    world.live = live
                    return
                }
                let deadline = start.addingTimeInterval(duration)
                guard now >= deadline else {
                    world.live = live
                    return
                }
                enterRecall(&live, now: deadline)
            case .recall:
                let deadline = live.phaseStartedAt.addingTimeInterval(live.recallDuration)
                guard now >= deadline else {
                    world.live = live
                    return
                }
                enterCloseBeat(&live, now: deadline)
            case .focus, .closeBeat:
                world.live = live
                return
            }
        }
    }

    /// Cold launch on iPhone: freeze an unpaused live session before UI.
    public mutating func pauseUnpausedLiveOnProcessStart(now: Date) {
        guard world.live?.isPaused == false else { return }
        try? apply(.pauseForRecovery, now: now)
    }

    public func status(now: Date, calendar: Calendar = .current) -> SessionStatus {
        Self.sessionStatus(world, now: now, calendar: calendar)
    }

    public static func sessionStatus(_ world: World, now: Date, calendar: Calendar = .current) -> SessionStatus {
        let today = world.todayFocusSeconds(now: now, calendar: calendar)
        let lastIntention = world.profile.lastIntention
        guard let live = world.live else {
            return SessionStatus(
                phase: nil,
                isPaused: false,
                intention: lastIntention,
                lastIntention: lastIntention,
                elapsed: 0,
                remaining: nil,
                phaseDuration: nil,
                focusSeconds: 0,
                breakSeconds: nil,
                earnedBreakSeconds: 0,
                captures: [],
                recallText: "",
                todayFocusSeconds: today,
                ratio: world.profile.breakRatio
            )
        }
        return viewStatus(live, now: now, todayFocusSeconds: today, lastIntention: lastIntention)
    }

    public static func viewStatus(_ live: SessionSnapshot, now: Date) -> SessionStatus {
        viewStatus(live, now: now, todayFocusSeconds: 0, lastIntention: live.intention)
    }

    public static func viewStatus(
        _ live: SessionSnapshot,
        now: Date,
        todayFocusSeconds: TimeInterval,
        lastIntention: String
    ) -> SessionStatus {
        let clock = live.pausedAt ?? now
        if live.isPaused {
            let focus =
                live.phase == .focus
                ? (live.frozenElapsed ?? focusElapsed(live, now: clock))
                : completedFocus(live)
            let earned = BreakMath.earnedBreak(focus: focus, ratio: live.breakRatio)
            return SessionStatus(
                phase: live.phase,
                isPaused: true,
                intention: live.intention,
                lastIntention: lastIntention,
                elapsed: live.frozenElapsed ?? elapsed(live, now: clock),
                remaining: live.frozenRemaining ?? remaining(live, now: clock),
                phaseDuration: phaseDuration(live),
                focusSeconds: focus,
                breakSeconds: live.breakDuration,
                earnedBreakSeconds: earned,
                captures: live.captures,
                recallText: live.recallText,
                todayFocusSeconds: todayFocusSeconds,
                ratio: live.breakRatio
            )
        }

        let focus = focusElapsed(live, now: now)
        let earned = BreakMath.earnedBreak(focus: focus, ratio: live.breakRatio)
        return SessionStatus(
            phase: live.phase,
            isPaused: false,
            intention: live.intention,
            lastIntention: lastIntention,
            elapsed: elapsed(live, now: now),
            remaining: remaining(live, now: now),
            phaseDuration: phaseDuration(live),
            focusSeconds: focus,
            breakSeconds: live.breakDuration,
            earnedBreakSeconds: earned,
            captures: live.captures,
            recallText: live.recallText,
            todayFocusSeconds: todayFocusSeconds,
            ratio: live.breakRatio
        )
    }

    // MARK: - Events

    private mutating func start(intention: String, now: Date) throws {
        if world.live != nil { throw EngineError.alreadyRunning }
        let trimmed = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? world.profile.lastIntention : trimmed
        world.profile.lastIntention = name
        world.live = SessionSnapshot(
            id: UUID(),
            intention: name,
            phase: .prime,
            breakRatio: world.profile.breakRatio,
            startedAt: now,
            phaseStartedAt: now,
            focusStartedAt: nil,
            focusEndedAt: nil,
            breakStartedAt: nil,
            breakDuration: nil,
            captures: [],
            primeDuration: world.config.primeSeconds,
            recallDuration: world.config.recallSeconds
        )
    }

    private mutating func pauseForRecovery(now: Date) {
        guard var live = world.live, !live.isPaused else { return }
        let view = Self.viewStatus(live, now: now)
        live.pausedAt = now
        live.frozenElapsed = view.elapsed
        live.frozenRemaining = view.remaining
        world.live = live
    }

    private mutating func continuePaused(now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        guard live.isPaused else { throw EngineError.notPaused }

        switch live.phase {
        case .prime:
            let remaining = live.frozenRemaining ?? max(0, live.primeDuration - (live.frozenElapsed ?? 0))
            let elapsed = live.primeDuration - remaining
            live.phaseStartedAt = now.addingTimeInterval(-elapsed)
        case .focus:
            let elapsed = live.frozenElapsed ?? 0
            let start = now.addingTimeInterval(-elapsed)
            live.focusStartedAt = start
            live.phaseStartedAt = start
        case .onBreak:
            let duration = live.breakDuration ?? 0
            let remaining = live.frozenRemaining ?? max(0, duration - (live.frozenElapsed ?? 0))
            let elapsed = duration - remaining
            let start = now.addingTimeInterval(-elapsed)
            live.breakStartedAt = start
            live.phaseStartedAt = start
        case .recall:
            let remaining = live.frozenRemaining ?? max(0, live.recallDuration - (live.frozenElapsed ?? 0))
            let elapsed = live.recallDuration - remaining
            live.phaseStartedAt = now.addingTimeInterval(-elapsed)
        case .closeBeat:
            live.phaseStartedAt = now
        }

        live.lastResumedAt = now
        live.pausedAt = nil
        live.frozenElapsed = nil
        live.frozenRemaining = nil
        world.live = live
    }

    private mutating func stopFocus(now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        guard live.phase == .focus else { throw EngineError.notFocus }
        let clock = live.pausedAt ?? now
        let focus =
            live.isPaused
            ? (live.frozenElapsed ?? Self.focusElapsed(live, now: clock))
            : Self.focusElapsed(live, now: now)
        live.focusEndedAt = live.isPaused ? live.pausedAt : now
        if live.focusStartedAt == nil {
            live.focusStartedAt = (live.focusEndedAt ?? now).addingTimeInterval(-focus)
        }
        live.breakDuration = BreakMath.earnedBreak(focus: focus, ratio: live.breakRatio)
        live.breakStartedAt = now
        live.phase = .onBreak
        live.phaseStartedAt = now
        Self.clearFreeze(&live)
        world.live = live
    }

    private mutating func skip(now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        switch live.phase {
        case .prime:
            enterFocus(&live, now: now)
            world.live = live
        case .onBreak:
            enterRecall(&live, now: now)
            world.live = live
        case .recall:
            enterCloseBeat(&live, now: now)
            world.live = live
        case .focus:
            try stopFocus(now: now)
        case .closeBeat:
            recordCompletion(live, now: now)
            world.live = nil
        }
    }

    private mutating func cancel() throws {
        guard world.live != nil else { throw EngineError.nothingRunning }
        world.live = nil
    }

    private mutating func restart(now: Date) throws {
        guard let live = world.live else { throw EngineError.nothingRunning }
        guard live.isPaused else { throw EngineError.notPaused }
        let intention = live.intention
        world.live = nil
        try start(intention: intention, now: now)
    }

    private mutating func setLastIntention(_ text: String) throws {
        guard world.live == nil else { throw EngineError.notIdle }
        world.profile.lastIntention = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func configureFocusGuard(_ config: FocusGuardConfiguration) throws {
        guard world.live == nil else { throw EngineError.notIdle }
        var next = config
        next.bundleIdentifiers = FocusGuard.normalize(config.bundleIdentifiers)
        world.config.focusGuard = next
    }

    private mutating func capture(_ text: String, now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        guard live.phase == .focus else { throw EngineError.cannotCapture }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError.emptyCapture }
        live.captures.append(CaptureItem(text: trimmed, createdAt: now))
        world.live = live
    }

    private mutating func setRecallText(_ text: String) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        guard live.phase == .recall else { throw EngineError.cannotSetRecallText }
        live.recallText = text
        world.live = live
    }

    // MARK: - Transitions

    private func enterFocus(_ live: inout SessionSnapshot, now: Date) {
        live.phase = .focus
        live.phaseStartedAt = now
        live.focusStartedAt = now
        Self.clearFreeze(&live)
    }

    private func enterRecall(_ live: inout SessionSnapshot, now: Date) {
        live.phase = .recall
        live.phaseStartedAt = now
        Self.clearFreeze(&live)
    }

    private mutating func enterCloseBeat(_ live: inout SessionSnapshot, now: Date) {
        live.phase = .closeBeat
        live.phaseStartedAt = now
        Self.clearFreeze(&live)
    }

    private mutating func recordCompletion(_ live: SessionSnapshot, now: Date) {
        let focus = Self.completedFocus(live)
        let recall = live.recallText.trimmingCharacters(in: .whitespacesAndNewlines)
        let completed = CompletedSession(
            id: live.id,
            intention: live.intention,
            focusSeconds: focus,
            breakSeconds: live.breakDuration ?? 0,
            captureCount: live.captures.count,
            recallText: recall.isEmpty ? nil : recall,
            endedAt: live.focusEndedAt ?? now,
            captures: live.captures
        )
        world.history.append(completed)
        world.profile = ProfileRecorder.apply(world.profile, focusSeconds: focus)
    }

    private static func clearFreeze(_ live: inout SessionSnapshot) {
        live.pausedAt = nil
        live.frozenElapsed = nil
        live.frozenRemaining = nil
    }

    private static func elapsed(_ live: SessionSnapshot, now: Date) -> TimeInterval {
        switch live.phase {
        case .prime:
            return max(0, now.timeIntervalSince(live.phaseStartedAt))
        case .focus:
            return focusElapsed(live, now: now)
        case .onBreak:
            let duration = live.breakDuration ?? 0
            let raw = live.breakStartedAt.map { now.timeIntervalSince($0) } ?? 0
            return min(max(0, raw), duration)
        case .recall:
            return max(0, now.timeIntervalSince(live.phaseStartedAt))
        case .closeBeat:
            return completedFocus(live)
        }
    }

    private static func remaining(_ live: SessionSnapshot, now: Date) -> TimeInterval? {
        switch live.phase {
        case .prime:
            return max(0, live.primeDuration - now.timeIntervalSince(live.phaseStartedAt))
        case .onBreak:
            let duration = live.breakDuration ?? 0
            let raw = live.breakStartedAt.map { now.timeIntervalSince($0) } ?? 0
            return max(0, duration - raw)
        case .recall:
            return max(0, live.recallDuration - now.timeIntervalSince(live.phaseStartedAt))
        case .focus, .closeBeat:
            return nil
        }
    }

    private static func phaseDuration(_ live: SessionSnapshot) -> TimeInterval? {
        switch live.phase {
        case .prime: return live.primeDuration
        case .onBreak: return live.breakDuration
        case .recall: return live.recallDuration
        case .focus, .closeBeat: return nil
        }
    }

    private static func focusElapsed(_ live: SessionSnapshot, now: Date) -> TimeInterval {
        if let ended = live.focusEndedAt, let started = live.focusStartedAt {
            return max(0, ended.timeIntervalSince(started))
        }
        if live.phase == .focus, let started = live.focusStartedAt {
            return max(0, now.timeIntervalSince(started))
        }
        return completedFocus(live)
    }

    private static func completedFocus(_ live: SessionSnapshot) -> TimeInterval {
        guard let start = live.focusStartedAt else { return 0 }
        let end = live.focusEndedAt ?? start
        return max(0, end.timeIntervalSince(start))
    }
}

public enum ProfileRecorder {
    public static func apply(_ profile: Profile, focusSeconds: TimeInterval) -> Profile {
        var next = profile
        if next.sessionCount < WorldPersistenceLimits.maximumCounter {
            next.sessionCount += 1
        } else {
            next.sessionCount = WorldPersistenceLimits.maximumCounter
        }
        let total = next.totalFocusSeconds + focusSeconds
        if total == .infinity || total > WorldPersistenceLimits.maximumAggregateSeconds {
            next.totalFocusSeconds = WorldPersistenceLimits.maximumAggregateSeconds
        } else {
            next.totalFocusSeconds = total
        }
        next.lastNote = nil
        return next
    }
}
