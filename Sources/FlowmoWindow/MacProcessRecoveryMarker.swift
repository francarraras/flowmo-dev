import Darwin
import FlowmoCore
import Foundation

enum MacProcessRecoveryError: LocalizedError {
    case cannotOpen(String)
    case cannotInspect(String)
    case unsafeTarget(String)
    case tooLarge(actual: Int64, maximum: Int64)
    case cannotRead(String)
    case malformed
    case unsupportedVersion(Int)
    case cannotInspectProcess(Int32, String)
    case cannotWrite(String)
    case lifetimeClaimUnavailable(String)
    case unsafeLifetimeClaim(String)
    case claimContended
    case ownershipLost

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let reason):
            return "Could not open the Mac recovery marker: \(reason)."
        case .cannotInspect(let reason):
            return "Could not inspect the Mac recovery marker: \(reason)."
        case .unsafeTarget(let reason):
            return "Unsafe Mac recovery marker: \(reason)."
        case .tooLarge(let actual, let maximum):
            return "The Mac recovery marker is \(actual) bytes; the maximum is \(maximum)."
        case .cannotRead(let reason):
            return "Could not read the Mac recovery marker: \(reason)."
        case .malformed:
            return "The Mac recovery marker is malformed."
        case .unsupportedVersion(let version):
            return "The Mac recovery marker version \(version) is unsupported."
        case .cannotInspectProcess(let pid, let reason):
            return "Could not inspect recovery process \(pid): \(reason)."
        case .cannotWrite(let reason):
            return "Could not write the Mac recovery marker: \(reason)."
        case .lifetimeClaimUnavailable(let reason):
            return "Could not acquire the Mac recovery lifetime claim: \(reason)."
        case .unsafeLifetimeClaim(let reason):
            return "Unsafe Mac recovery lifetime claim: \(reason)."
        case .claimContended:
            return "Another process currently owns the Mac recovery marker."
        case .ownershipLost:
            return "The Mac recovery marker is no longer owned by this process."
        }
    }
}

/// The canonical recovery marker was refreshed successfully, but Delete All
/// could not remove every exact crash-orphaned marker write. This is a privacy
/// cleanup failure, not a loss of lifecycle ownership.
enum MacProcessRecoveryDataDeletionError: LocalizedError {
    case cleanupIncomplete(String)

    var errorDescription: String? {
        switch self {
        case .cleanupIncomplete(let reason):
            return "Mac recovery data cleanup was incomplete: \(reason)."
        }
    }
}

/// Owns the Mac host's crash marker for one store. Every public mutation is
/// called while `Store.update` holds `world.lock`.
@MainActor
final class MacProcessRecoveryMarker {
    static let maximumMarkerBytes: Int64 = 4 * 1024

    struct ProcessIdentity: Codable, Equatable {
        let pid: Int32
        let startedAtSeconds: UInt64
        let startedAtMicroseconds: UInt64
    }

    struct Record: Codable, Equatable {
        static let currentVersion = 1

        let version: Int
        let ownerID: UUID
        let pid: Int32
        let processStartedAtSeconds: UInt64
        let processStartedAtMicroseconds: UInt64
        let liveSessionID: UUID?
        let lastObservedAt: Date

        var processIdentity: ProcessIdentity {
            ProcessIdentity(
                pid: pid,
                startedAtSeconds: processStartedAtSeconds,
                startedAtMicroseconds: processStartedAtMicroseconds
            )
        }
    }

    private struct LegacyRecord: Codable {
        let pid: Int32
        let liveSessionID: UUID?
        let lastObservedAt: Date
    }

    enum ClaimPreparation: Equatable {
        case prepared
        case contended
    }

    private enum PreviousMarker {
        case absent
        case versioned(Record)
        case legacy(LegacyRecord)
    }

    private struct PendingClaim {
        let identity: ProcessIdentity
        let sessionID: UUID?
        let observedAt: Date
    }

    private let url: URL
    private let lifetimeLockURL: URL
    private let ownerID: UUID
    private let processID: Int32
    private let identityLookup: (Int32) throws -> ProcessIdentity?
    private var processIdentity: ProcessIdentity?
    private var pendingClaim: PendingClaim?
    private var lifetimeClaimFileDescriptor: Int32?
    private var ownsMarker = false
    private var trackedSessionID: UUID?
    private var lastObservedAt: Date?

    var ownsLifecycle: Bool {
        ownsMarker
    }

    var claimedLifetimeFileDescriptor: Int32? {
        lifetimeClaimFileDescriptor
    }

    init(store: Store) {
        self.url = store.root.appendingPathComponent("mac-process-recovery.json")
        self.lifetimeLockURL = store.root.appendingPathComponent("mac-process-recovery.lock")
        self.ownerID = UUID()
        self.processID = getpid()
        self.identityLookup = Self.lookupProcessIdentity
    }

    init(
        store: Store,
        ownerID: UUID,
        processID: Int32,
        processIdentity: ProcessIdentity,
        identityLookup: @escaping (Int32) throws -> ProcessIdentity?
    ) {
        self.url = store.root.appendingPathComponent("mac-process-recovery.json")
        self.lifetimeLockURL = store.root.appendingPathComponent("mac-process-recovery.lock")
        self.ownerID = ownerID
        self.processID = processID
        self.processIdentity = processIdentity
        self.identityLookup = identityLookup
    }

    deinit {
        if let lifetimeClaimFileDescriptor {
            _ = flock(lifetimeClaimFileDescriptor, LOCK_UN)
            close(lifetimeClaimFileDescriptor)
        }
    }

    /// Prepare Mac-host ownership. The kernel-held lifetime lock is the sole
    /// authority for a concurrent Mac owner; JSON is crash metadata only.
    /// Ownership is committed after `Store.update` persists the recovered world.
    func prepareClaim(
        _ engine: inout Engine,
        now: Date,
        trackLiveSession: Bool = true
    ) throws -> ClaimPreparation {
        if ownsMarker { return .prepared }
        try requireFinite(now)
        guard try acquireLifetimeClaim() else { return .contended }

        let currentIdentity = try resolvedCurrentIdentity()
        let previous = try previousMarker()
        switch previous {
        case .versioned(let record):
            if trackLiveSession, record.liveSessionID == engine.world.live?.id {
                try freeze(&engine, at: record.lastObservedAt, noLaterThan: now)
            }
        case .legacy(let record):
            if trackLiveSession, record.liveSessionID == engine.world.live?.id {
                try freeze(&engine, at: record.lastObservedAt, noLaterThan: now)
            }
        case .absent:
            break
        }

        let sessionID = trackLiveSession ? engine.world.live?.id : nil
        try writeRecord(identity: currentIdentity, sessionID: sessionID, observedAt: now)
        pendingClaim = PendingClaim(identity: currentIdentity, sessionID: sessionID, observedAt: now)
        return .prepared
    }

    /// Called only after the `Store.update` containing `prepareClaim` succeeds.
    func commitPreparedClaim() {
        guard let pendingClaim else { return }
        processIdentity = pendingClaim.identity
        trackedSessionID = pendingClaim.sessionID
        lastObservedAt = pendingClaim.observedAt
        ownsMarker = true
        self.pendingClaim = nil
    }

    /// Write-ahead observation for a live session. Nil observations are used
    /// only after the terminal world is already durable.
    func recordObservation(_ sessionID: UUID?, at now: Date) throws {
        guard ownsMarker else { throw MacProcessRecoveryError.ownershipLost }
        try refreshOwnership(for: sessionID, at: now)
    }

    /// Clear prior session metadata and exact crash-orphaned marker temp files
    /// after Delete All. The caller holds `world.lock` and supplies the actual
    /// locked world's current session identity.
    func recordDataDeletion(_ sessionID: UUID?, at now: Date) throws {
        try recordObservation(sessionID, at: now)
        try removeOrphanedWrites()
    }

    /// Re-establish the on-disk marker after a transient lifecycle failure.
    func refreshOwnership(for sessionID: UUID?, at now: Date) throws {
        guard ownsMarker, let processIdentity else { throw MacProcessRecoveryError.ownershipLost }
        try requireFinite(now)
        try writeRecord(identity: processIdentity, sessionID: sessionID, observedAt: now)
        trackedSessionID = sessionID
        lastObservedAt = now
    }

    func needsObservation(for sessionID: UUID?) -> Bool {
        guard ownsMarker else { return false }
        return trackedSessionID != sessionID
    }

    func needsHeartbeat(at now: Date) -> Bool {
        guard ownsMarker, trackedSessionID != nil, let lastObservedAt else { return false }
        let interval = now.timeIntervalSince(lastObservedAt)
        return interval < 0 || interval >= 5
    }

    /// Clear only this exact process owner's marker. The caller holds
    /// `world.lock`, after the recovery pause is durable.
    func finishNormally() throws {
        guard ownsMarker, let processIdentity else { return }
        guard let diskRecord = try readCurrentRecord() else {
            clearOwnership()
            return
        }
        guard diskRecord.ownerID == ownerID, diskRecord.processIdentity == processIdentity else {
            throw MacProcessRecoveryError.ownershipLost
        }
        guard unlink(url.path) == 0 else {
            if errno == ENOENT {
                clearOwnership()
                return
            }
            throw MacProcessRecoveryError.cannotWrite(Self.posixMessage())
        }
        clearOwnership()
    }

    private func previousMarker() throws -> PreviousMarker {
        guard let data = try readMarkerData() else { return .absent }
        let decoder = JSONDecoder()
        if let record = try? decoder.decode(Record.self, from: data) {
            guard record.version == Record.currentVersion else {
                throw MacProcessRecoveryError.unsupportedVersion(record.version)
            }
            try validate(record)
            return .versioned(record)
        }
        guard let legacy = try? decoder.decode(LegacyRecord.self, from: data) else {
            throw MacProcessRecoveryError.malformed
        }
        try validate(legacy)
        return .legacy(legacy)
    }

    private func readCurrentRecord() throws -> Record? {
        guard let data = try readMarkerData() else { return nil }
        let record: Record
        do {
            record = try JSONDecoder().decode(Record.self, from: data)
        } catch {
            throw MacProcessRecoveryError.malformed
        }
        guard record.version == Record.currentVersion else {
            throw MacProcessRecoveryError.unsupportedVersion(record.version)
        }
        try validate(record)
        return record
    }

    private func readMarkerData() throws -> Data? {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP {
                throw MacProcessRecoveryError.unsafeTarget("the marker must not be a symbolic link")
            }
            throw MacProcessRecoveryError.cannotOpen(Self.posixMessage())
        }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw MacProcessRecoveryError.cannotInspect(Self.posixMessage())
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw MacProcessRecoveryError.unsafeTarget("the marker must be a regular file")
        }
        guard info.st_size >= 0 else {
            throw MacProcessRecoveryError.unsafeTarget("the marker reported a negative size")
        }
        guard info.st_size <= Self.maximumMarkerBytes else {
            throw MacProcessRecoveryError.tooLarge(actual: info.st_size, maximum: Self.maximumMarkerBytes)
        }

        let maximum = Int(Self.maximumMarkerBytes)
        var data = Data()
        data.reserveCapacity(min(Int(info.st_size), maximum))
        var buffer = [UInt8](repeating: 0, count: maximum + 1)
        while true {
            let remaining = maximum + 1 - data.count
            let amount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fd, bytes.baseAddress, min(bytes.count, remaining))
            }
            if amount == 0 { break }
            if amount < 0 {
                if errno == EINTR { continue }
                throw MacProcessRecoveryError.cannotRead(Self.posixMessage())
            }
            data.append(contentsOf: buffer.prefix(amount))
            if data.count > maximum {
                throw MacProcessRecoveryError.tooLarge(
                    actual: Int64(data.count), maximum: Self.maximumMarkerBytes
                )
            }
        }
        return data
    }

    private func writeRecord(identity: ProcessIdentity, sessionID: UUID?, observedAt: Date) throws {
        try requireFinite(observedAt)
        let record = Record(
            version: Record.currentVersion,
            ownerID: ownerID,
            pid: identity.pid,
            processStartedAtSeconds: identity.startedAtSeconds,
            processStartedAtMicroseconds: identity.startedAtMicroseconds,
            liveSessionID: sessionID,
            lastObservedAt: observedAt
        )
        let data: Data
        do {
            data = try JSONEncoder().encode(record)
        } catch {
            throw MacProcessRecoveryError.cannotWrite(error.localizedDescription)
        }
        guard Int64(data.count) <= Self.maximumMarkerBytes else {
            throw MacProcessRecoveryError.tooLarge(
                actual: Int64(data.count), maximum: Self.maximumMarkerBytes
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            throw MacProcessRecoveryError.cannotWrite(error.localizedDescription)
        }
        try rejectUnsafeExistingTarget()
        let temporary = url.deletingLastPathComponent().appendingPathComponent(
            ".mac-process-recovery.write-\(UUID().uuidString).tmp"
        )
        let fd = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard fd >= 0 else { throw MacProcessRecoveryError.cannotWrite(Self.posixMessage()) }
        var keepTemporary = true
        defer {
            close(fd)
            if keepTemporary { _ = unlink(temporary.path) }
        }

        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let amount = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if amount < 0 {
                    if errno == EINTR { continue }
                    throw MacProcessRecoveryError.cannotWrite(Self.posixMessage())
                }
                guard amount > 0 else {
                    throw MacProcessRecoveryError.cannotWrite("write returned zero bytes")
                }
                offset += amount
            }
        }
        guard fsync(fd) == 0 else { throw MacProcessRecoveryError.cannotWrite(Self.posixMessage()) }
        try rejectUnsafeExistingTarget()
        guard rename(temporary.path, url.path) == 0 else {
            throw MacProcessRecoveryError.cannotWrite(Self.posixMessage())
        }
        keepTemporary = false
    }

    private func rejectUnsafeExistingTarget() throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                throw MacProcessRecoveryError.unsafeTarget("the marker must be a regular file")
            }
            return
        }
        guard errno == ENOENT else {
            throw MacProcessRecoveryError.cannotInspect(Self.posixMessage())
        }
    }

    private func removeOrphanedWrites() throws {
        let candidates: [URL]
        do {
            candidates = try FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(),
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw MacProcessRecoveryDataDeletionError.cleanupIncomplete(
                "temporary writes could not be enumerated: \(error.localizedDescription)"
            )
        }

        var failures: [String] = []
        for candidate in candidates where Self.isOwnedTemporaryWrite(candidate.lastPathComponent) {
            if unlink(candidate.path) != 0 {
                failures.append("\(candidate.lastPathComponent): \(Self.posixMessage())")
            }
        }
        if !failures.isEmpty {
            throw MacProcessRecoveryDataDeletionError.cleanupIncomplete(
                failures.joined(separator: "; ")
            )
        }
    }

    private static func isOwnedTemporaryWrite(_ name: String) -> Bool {
        let prefix = ".mac-process-recovery.write-"
        let suffix = ".tmp"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        let tokenStart = name.index(name.startIndex, offsetBy: prefix.count)
        let tokenEnd = name.index(name.endIndex, offsetBy: -suffix.count)
        guard tokenStart < tokenEnd else { return false }
        return UUID(uuidString: String(name[tokenStart..<tokenEnd])) != nil
    }

    private func validate(_ record: Record) throws {
        guard record.pid > 0, record.processStartedAtMicroseconds < 1_000_000 else {
            throw MacProcessRecoveryError.malformed
        }
        try requireFinite(record.lastObservedAt)
    }

    private func validate(_ record: LegacyRecord) throws {
        guard record.pid > 0 else { throw MacProcessRecoveryError.malformed }
        try requireFinite(record.lastObservedAt)
    }

    private func requireFinite(_ date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw MacProcessRecoveryError.malformed
        }
    }

    private func resolvedCurrentIdentity() throws -> ProcessIdentity {
        if let processIdentity { return processIdentity }
        guard let identity = try identityLookup(processID), identity.pid == processID else {
            throw MacProcessRecoveryError.cannotInspectProcess(processID, "process not found")
        }
        processIdentity = identity
        return identity
    }

    /// Open and lock one stable, empty inode. The file is deliberately never
    /// unlinked by lifecycle finish or Delete All: unlinking a held lock would
    /// let another process lock a replacement pathname concurrently.
    private func acquireLifetimeClaim() throws -> Bool {
        if lifetimeClaimFileDescriptor != nil { return true }
        do {
            try FileManager.default.createDirectory(
                at: lifetimeLockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw MacProcessRecoveryError.lifetimeClaimUnavailable(error.localizedDescription)
        }

        let fd = open(
            lifetimeLockURL.path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard fd >= 0 else {
            if errno == ELOOP || errno == EISDIR {
                throw MacProcessRecoveryError.unsafeLifetimeClaim(
                    "the lifetime lock must be a regular file, not a symbolic link or directory"
                )
            }
            throw MacProcessRecoveryError.lifetimeClaimUnavailable(Self.posixMessage())
        }

        func fail(_ error: Error) throws -> Bool {
            close(fd)
            throw error
        }

        var opened = stat()
        guard fstat(fd, &opened) == 0 else {
            return try fail(MacProcessRecoveryError.lifetimeClaimUnavailable(Self.posixMessage()))
        }
        guard (opened.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            return try fail(
                MacProcessRecoveryError.unsafeLifetimeClaim("the lifetime lock must be a regular file")
            )
        }
        guard opened.st_uid == geteuid(), opened.st_nlink == 1, opened.st_size == 0 else {
            return try fail(
                MacProcessRecoveryError.unsafeLifetimeClaim(
                    "the lifetime lock must be an empty, single-link file owned by the current user"
                )
            )
        }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            close(fd)
            if lockError == EWOULDBLOCK || lockError == EAGAIN { return false }
            errno = lockError
            throw MacProcessRecoveryError.lifetimeClaimUnavailable(Self.posixMessage())
        }
        guard fchmod(fd, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            let modeError = errno
            _ = flock(fd, LOCK_UN)
            close(fd)
            errno = modeError
            throw MacProcessRecoveryError.lifetimeClaimUnavailable(Self.posixMessage())
        }

        var path = stat()
        guard lstat(lifetimeLockURL.path, &path) == 0 else {
            let inspectError = errno
            _ = flock(fd, LOCK_UN)
            close(fd)
            errno = inspectError
            throw MacProcessRecoveryError.lifetimeClaimUnavailable(Self.posixMessage())
        }
        guard
            (path.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            path.st_dev == opened.st_dev,
            path.st_ino == opened.st_ino,
            path.st_nlink == 1
        else {
            _ = flock(fd, LOCK_UN)
            close(fd)
            throw MacProcessRecoveryError.unsafeLifetimeClaim(
                "the lifetime lock pathname changed while ownership was prepared"
            )
        }

        lifetimeClaimFileDescriptor = fd
        return true
    }

    private func freeze(_ engine: inout Engine, at observedAt: Date, noLaterThan recoveryNow: Date) throws {
        guard let live = engine.world.live, !live.isPaused else { return }
        let observedBoundary = min(observedAt, recoveryNow)
        let resumeBoundary = min(live.lastResumedAt ?? live.phaseStartedAt, recoveryNow)
        let freezeAt = max(live.phaseStartedAt, max(observedBoundary, resumeBoundary))
        try engine.apply(.pauseForRecovery, now: freezeAt)
    }

    private func clearOwnership() {
        ownsMarker = false
        trackedSessionID = nil
        lastObservedAt = nil
        processIdentity = nil
        pendingClaim = nil
        if let lifetimeClaimFileDescriptor {
            _ = flock(lifetimeClaimFileDescriptor, LOCK_UN)
            close(lifetimeClaimFileDescriptor)
            self.lifetimeClaimFileDescriptor = nil
        }
    }

    private static func lookupProcessIdentity(_ pid: Int32) throws -> ProcessIdentity? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        errno = 0
        let count = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        if count == Int32(MemoryLayout<proc_bsdinfo>.size) {
            return ProcessIdentity(
                pid: pid,
                startedAtSeconds: info.pbi_start_tvsec,
                startedAtMicroseconds: info.pbi_start_tvusec
            )
        }
        if kill(pid, 0) < 0, errno == ESRCH { return nil }
        throw MacProcessRecoveryError.cannotInspectProcess(pid, Self.posixMessage())
    }

    private static func posixMessage() -> String {
        String(cString: strerror(errno))
    }
}
