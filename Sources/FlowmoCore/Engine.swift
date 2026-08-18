import Foundation

public enum BreakMath {
    public static func earnedBreak(focus: TimeInterval, ratio: Double) -> TimeInterval {
        guard ratio > 0 else { return 0 }
        return max(0, focus / ratio)
    }
}

public struct Engine: Equatable, Sendable {
    public var world: World

    public init(world: World = .empty) {
        self.world = world
    }

    public mutating func apply(_ event: Event, now: Date) throws {
        sync(now: now)
        switch event {
        case .start(let label):
            try start(label: label, now: now)
        case .pause:
            try pause(now: now)
        case .resume:
            try resume(now: now)
        case .stopEncoding:
            try stopEncoding(now: now)
        case .skip:
            try skip(now: now)
        case .cancel:
            try cancel()
        case .capture(let text):
            try capture(text, now: now)
        }
    }

    /// Move timed phases forward if their clock has run out.
    public mutating func sync(now: Date) {
        guard var live = world.live else { return }

        switch live.state {
        case .priming:
            if now.timeIntervalSince(live.phaseStartedAt) >= live.primeDuration {
                enterEncoding(&live, now: now)
                world.live = live
            }
        case .onBreak:
            if let start = live.breakStartedAt, let duration = live.breakDuration,
               now.timeIntervalSince(start) >= duration {
                enterRecall(&live, now: now)
                world.live = live
            }
        case .recall:
            if now.timeIntervalSince(live.phaseStartedAt) >= live.recallDuration {
                finish(live, now: now)
            }
        case .encoding, .paused:
            break
        }
    }

    public func status(now: Date) -> ViewStatus? {
        guard let live = world.live else { return nil }
        return Self.viewStatus(live, now: now)
    }

    public static func viewStatus(_ live: SessionSnapshot, now: Date) -> ViewStatus {
        let focus = focusElapsed(live, now: now)
        switch live.state {
        case .priming:
            let elapsed = now.timeIntervalSince(live.phaseStartedAt)
            return ViewStatus(
                state: .priming,
                label: live.label,
                elapsed: elapsed,
                remaining: max(0, live.primeDuration - elapsed),
                focusSeconds: 0,
                breakSeconds: nil,
                captures: live.captures,
                ratio: live.breakRatio
            )
        case .encoding:
            return ViewStatus(
                state: .encoding,
                label: live.label,
                elapsed: focus,
                remaining: nil,
                focusSeconds: focus,
                breakSeconds: nil,
                captures: live.captures,
                ratio: live.breakRatio
            )
        case .paused:
            let elapsed = live.pausedElapsed ?? 0
            return ViewStatus(
                state: .paused,
                label: live.label,
                elapsed: elapsed,
                remaining: nil,
                focusSeconds: elapsed,
                breakSeconds: nil,
                captures: live.captures,
                ratio: live.breakRatio
            )
        case .onBreak:
            let duration = live.breakDuration ?? 0
            let elapsed = live.breakStartedAt.map { now.timeIntervalSince($0) } ?? 0
            return ViewStatus(
                state: .onBreak,
                label: live.label,
                elapsed: min(elapsed, duration),
                remaining: max(0, duration - elapsed),
                focusSeconds: completedFocus(live),
                breakSeconds: duration,
                captures: live.captures,
                ratio: live.breakRatio
            )
        case .recall:
            let elapsed = now.timeIntervalSince(live.phaseStartedAt)
            return ViewStatus(
                state: .recall,
                label: live.label,
                elapsed: elapsed,
                remaining: max(0, live.recallDuration - elapsed),
                focusSeconds: completedFocus(live),
                breakSeconds: live.breakDuration,
                captures: live.captures,
                ratio: live.breakRatio
            )
        }
    }

    // MARK: - Events

    private mutating func start(label: String, now: Date) throws {
        if world.live != nil { throw EngineError.alreadyRunning }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "focus" : trimmed
        world.live = SessionSnapshot(
            id: UUID(),
            label: name,
            state: .priming,
            breakRatio: world.profile.breakRatio,
            startedAt: now,
            phaseStartedAt: now,
            encodingStartedAt: nil,
            encodingEndedAt: nil,
            pausedElapsed: nil,
            breakStartedAt: nil,
            breakDuration: nil,
            captures: [],
            primeDuration: world.config.primeSeconds,
            recallDuration: world.config.recallSeconds
        )
    }

    private mutating func pause(now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        guard live.state == .encoding else { throw EngineError.cannotPause }
        live.pausedElapsed = Self.focusElapsed(live, now: now)
        live.state = .paused
        world.live = live
    }

    private mutating func resume(now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        guard live.state == .paused else { throw EngineError.notPaused }
        let elapsed = live.pausedElapsed ?? 0
        live.encodingStartedAt = now.addingTimeInterval(-elapsed)
        live.pausedElapsed = nil
        live.state = .encoding
        live.phaseStartedAt = live.encodingStartedAt ?? now
        world.live = live
    }

    private mutating func stopEncoding(now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        guard live.state == .encoding else { throw EngineError.notEncoding }
        let focus = Self.focusElapsed(live, now: now)
        live.encodingEndedAt = now
        live.breakDuration = BreakMath.earnedBreak(focus: focus, ratio: live.breakRatio)
        live.breakStartedAt = now
        live.state = .onBreak
        live.phaseStartedAt = now
        world.live = live
    }

    private mutating func skip(now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        switch live.state {
        case .priming:
            enterEncoding(&live, now: now)
            world.live = live
        case .onBreak:
            enterRecall(&live, now: now)
            world.live = live
        case .recall:
            finish(live, now: now)
        case .encoding:
            try stopEncoding(now: now)
        case .paused:
            throw EngineError.notEncoding
        }
    }

    private mutating func cancel() throws {
        guard world.live != nil else { throw EngineError.nothingRunning }
        world.live = nil
    }

    private mutating func capture(_ text: String, now: Date) throws {
        guard var live = world.live else { throw EngineError.nothingRunning }
        guard live.state == .encoding || live.state == .paused else {
            throw EngineError.cannotCapture
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError.emptyCapture }
        live.captures.append(CaptureItem(text: trimmed, createdAt: now))
        world.live = live
    }

    // MARK: - Transitions

    private func enterEncoding(_ live: inout SessionSnapshot, now: Date) {
        live.state = .encoding
        live.phaseStartedAt = now
        live.encodingStartedAt = now
        live.pausedElapsed = nil
    }

    private func enterRecall(_ live: inout SessionSnapshot, now: Date) {
        live.state = .recall
        live.phaseStartedAt = now
    }

    private mutating func finish(_ live: SessionSnapshot, now: Date) {
        let focus = Self.completedFocus(live)
        let breakTaken = live.breakDuration ?? 0
        let completed = CompletedSession(
            id: live.id,
            label: live.label,
            focusSeconds: focus,
            breakSeconds: breakTaken,
            captureCount: live.captures.count,
            endedAt: now
        )
        world.history.append(completed)
        world.profile = ProfileLearner.apply(world.profile, focusSeconds: focus)
        world.live = nil
    }

    private static func focusElapsed(_ live: SessionSnapshot, now: Date) -> TimeInterval {
        if live.state == .paused { return live.pausedElapsed ?? 0 }
        if let ended = live.encodingEndedAt, let started = live.encodingStartedAt {
            return ended.timeIntervalSince(started)
        }
        if let started = live.encodingStartedAt {
            return max(0, now.timeIntervalSince(started))
        }
        return 0
    }

    private static func completedFocus(_ live: SessionSnapshot) -> TimeInterval {
        guard let start = live.encodingStartedAt else { return 0 }
        let end = live.encodingEndedAt ?? start
        return max(0, end.timeIntervalSince(start))
    }
}

public enum ProfileLearner {
    public static let longSession: TimeInterval = 45 * 60
    public static let shortSession: TimeInterval = 20 * 60
    public static let step: Double = 0.25
    public static let minRatio: Double = 3
    public static let maxRatio: Double = 8

    public static func apply(_ profile: Profile, focusSeconds: TimeInterval) -> Profile {
        var next = profile
        next.sessionCount += 1
        next.totalFocusSeconds += focusSeconds
        next.recentFocusSeconds.append(focusSeconds)
        if next.recentFocusSeconds.count > 5 {
            next.recentFocusSeconds.removeFirst(next.recentFocusSeconds.count - 5)
        }

        let recent = next.recentFocusSeconds.suffix(3)
        guard recent.count == 3 else {
            next.lastNote = nil
            return next
        }

        if recent.allSatisfy({ $0 >= longSession }) {
            let before = next.breakRatio
            next.breakRatio = max(minRatio, next.breakRatio - step)
            if next.breakRatio < before {
                next.lastNote = "Last three sessions ran long, so the next break will be a bit longer (ratio \(format(next.breakRatio)))."
            }
        } else if recent.allSatisfy({ $0 <= shortSession }) {
            let before = next.breakRatio
            next.breakRatio = min(maxRatio, next.breakRatio + step)
            if next.breakRatio > before {
                next.lastNote = "Last three sessions were short, so the next break will be a bit shorter (ratio \(format(next.breakRatio)))."
            }
        } else {
            next.lastNote = nil
        }
        return next
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2g", value)
    }
}
