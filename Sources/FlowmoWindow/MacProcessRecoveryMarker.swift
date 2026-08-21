import Darwin
import Foundation
import FlowmoCore

/// Owns the Mac host's crash marker for one store. The marker is changed while
/// `Store.update` holds the world lock, so a relaunch cannot race recovery.
@MainActor
final class MacProcessRecoveryMarker {
    private struct Record: Codable {
        let pid: Int32
        let liveSessionID: UUID?
        let lastObservedAt: Date
    }

    private enum PreviousMarker {
        case absent
        case live
        case dead(Record)
        case malformed
    }

    private let url: URL
    private var ownsMarker = false
    private var trackedSessionID: UUID?
    private var lastObservedAt: Date?

    var ownsLifecycle: Bool {
        ownsMarker
    }

    init(store: Store) {
        url = store.root.appendingPathComponent("mac-process-recovery.json")
    }

    /// Claim Mac-host ownership. A dead marker pauses only the session that its
    /// former owner had observed, never a later CLI-only session.
    func claim(_ engine: inout Engine, now: Date) {
        guard !ownsMarker else { return }

        let previous = previousMarker(now: now)
        switch previous {
        case .dead(let record) where record.liveSessionID == engine.world.live?.id:
            freeze(&engine, at: record.lastObservedAt, noLaterThan: now)
        case .absent, .live, .dead, .malformed:
            break
        }

        guard case .live = previous else {
            trackedSessionID = engine.world.live?.id
            lastObservedAt = now
            writeRecord()
            ownsMarker = true
            return
        }
    }

    /// Record a durable observation after a state mutation. The last live
    /// identity is retained through terminal transitions so a crash before
    /// `Store` writes the terminal world still recovers that older live state.
    func recordObservation(_ sessionID: UUID?, at now: Date) {
        guard ownsMarker, let sessionID else { return }
        trackedSessionID = sessionID
        lastObservedAt = now
        writeRecord()
    }

    func needsObservation(for sessionID: UUID?) -> Bool {
        guard ownsMarker, let sessionID else { return false }
        return trackedSessionID != sessionID
    }

    func needsHeartbeat(at now: Date) -> Bool {
        guard ownsMarker, trackedSessionID != nil, let lastObservedAt else { return false }
        return now.timeIntervalSince(lastObservedAt) >= 5
    }

    /// Clear only this process's marker after its recovery pause is durable.
    func finishNormally() {
        guard ownsMarker else { return }
        try? FileManager.default.removeItem(at: url)
        ownsMarker = false
        trackedSessionID = nil
        lastObservedAt = nil
    }

    private func previousMarker(now: Date) -> PreviousMarker {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.pid > 0,
              record.lastObservedAt <= now else {
            return .malformed
        }
        return processIsAlive(record.pid) ? .live : .dead(record)
    }

    private func writeRecord() {
        let record = Record(
            pid: getpid(),
            liveSessionID: trackedSessionID,
            lastObservedAt: lastObservedAt ?? Date()
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func freeze(_ engine: inout Engine, at observedAt: Date, noLaterThan recoveryNow: Date) {
        guard let live = engine.world.live, !live.isPaused else { return }
        let freezeAt = min(recoveryNow, max(observedAt, live.phaseStartedAt))
        try? engine.apply(.pauseForRecovery, now: freezeAt)
    }

    private func processIsAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
