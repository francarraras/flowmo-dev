import Darwin
import Foundation

public struct Store: Sendable {
    private static let quarantinePrefix = "world.invalid-"
    private static let temporaryWritePrefix = ".world.write-"

    public let root: URL

    public static var `default`: Store {
        if let override = ProcessInfo.processInfo.environment["FLOWMO_HOME"], !override.isEmpty {
            return Store(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return Store(
                root: URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(".flowmo", isDirectory: true)
            )
        }
        #if os(macOS)
            return Store(
                root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                    ".flowmo", isDirectory: true))
        #else
            let support =
                FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return Store(root: support.appendingPathComponent("flowmo", isDirectory: true))
        #endif
    }

    public init(root: URL) {
        self.root = root
    }

    /// iPhone app + widget. Nil if the App Group is missing (spike failed).
    public static let phoneAppGroupID = "group.app.flowmo.phone"

    public static func phoneSharedRoot() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: phoneAppGroupID)?
            .appendingPathComponent("flowmo", isDirectory: true)
    }

    /// Migrate `world.json` once. Keep a valid destination; repair a corrupt one from a valid source.
    @discardableResult
    public static func migrateWorld(from oldRoot: URL, to newRoot: URL) throws -> Bool {
        let fm = FileManager.default
        let source = Store(root: oldRoot)
        let destination = Store(root: newRoot)
        let sourceExists = fm.fileExists(atPath: source.worldURL.path)

        if fm.fileExists(atPath: destination.worldURL.path) {
            do {
                _ = try destination.load()
                return false
            } catch {
                guard sourceExists else { throw error }
            }
        } else if !sourceExists {
            return false
        }

        let world = try source.load()
        return try destination.installMigratedWorldIfNeeded(world)
    }

    public func load() throws -> World {
        guard let data = try readWorldData() else { return .empty }
        try RawWorldValidation.validate(data)
        let world: World
        do {
            world = try JSONDecoder.flowmo.decode(World.self, from: data)
        } catch {
            throw StoreError.cannotDecodeWorld(error.localizedDescription)
        }
        try world.validateForPersistence()
        return world
    }

    public func save(_ world: World) throws {
        try withLock {
            try saveUnlocked(world)
        }
    }

    /// Mutate the world under `world.lock`. `afterPersist`, when supplied, runs
    /// after the new world is durable and before the lock is released. An error
    /// from that hook does not roll back an already-persisted world.
    public func update(
        _ body: (inout Engine) throws -> Void,
        afterPersist: ((Engine) throws -> Void)? = nil
    ) throws -> Engine {
        try withLock {
            var engine = Engine(world: try load())
            let before = engine.world
            try body(&engine)
            if engine.world != before {
                try saveUnlocked(engine.world)
            }
            try afterPersist?(engine)
            return engine
        }
    }

    /// A stable, validated JSON snapshot suitable for a user-requested export.
    public func exportCurrentWorldJSON() throws -> Data {
        try withLock {
            let world = try load()
            try world.validateForPersistence()
            let data = try JSONEncoder.flowmo.encode(world)
            try enforceEncodedSize(data)
            return data
        }
    }

    /// Preserve an invalid final target and replace it with a validated empty
    /// world. The original bytes (or unsafe filesystem entry) are never deleted.
    public func quarantineInvalidWorldAndReset() throws -> QuarantinedWorld {
        try withLock {
            let invalidReason: String
            do {
                _ = try load()
                throw StoreError.worldIsValid
            } catch StoreError.worldIsValid {
                throw StoreError.worldIsValid
            } catch {
                invalidReason = error.localizedDescription
            }
            return try quarantineInvalidWorldAndReplace(with: .empty, invalidReason: invalidReason)
        }
    }

    /// Delete the current session/history/profile state by atomically replacing
    /// it with `.empty`. Existing quarantines are deliberately preserved.
    /// A live session must be ended through the product loop first.
    @discardableResult
    public func resetToEmpty() throws -> StoreResetResult {
        try withLock {
            let world = try load()
            guard world.live == nil else { throw StoreError.liveSessionPreventsReset }
            try saveUnlocked(.empty)
            return StoreResetResult(
                worldURL: worldURL,
                resetAt: Date(),
                preservedQuarantineURLs: try quarantineURLs()
            )
        }
    }

    /// Explicit privacy deletion. Unlike `resetToEmpty`, this removes every
    /// Store-owned invalid-world recovery copy, crash-orphaned atomic-write
    /// file, and local aggregate-evidence artifact after atomically resetting
    /// the current world. A partial cleanup is surfaced with exact remaining
    /// URLs.
    @discardableResult
    public func deleteAllData() throws -> StoreDeletionResult {
        try withLock {
            let world = try load()
            guard world.live == nil else { throw StoreError.liveSessionPreventsReset }
            try saveUnlocked(.empty)

            var removedRecoveryArtifacts: [URL] = []
            var remainingRecoveryArtifacts: [URL] = []
            var remainingRecoveryArtifactsKnown = true
            var failureReasons: [String] = []
            do {
                let artifacts = try recoveryArtifactURLs()
                for artifact in artifacts {
                    if unlink(artifact.path) == 0 {
                        removedRecoveryArtifacts.append(artifact)
                    } else if errno != ENOENT {
                        remainingRecoveryArtifacts.append(artifact)
                        failureReasons.append(
                            "\(artifact.lastPathComponent): \(Self.posixMessage())"
                        )
                    }
                }
            } catch {
                remainingRecoveryArtifactsKnown = false
                failureReasons.append(
                    "Recovery artifacts could not be enumerated: \(error.localizedDescription)"
                )
            }

            var removedEvidenceArtifacts: [URL] = []
            var remainingEvidenceArtifacts: [URL] = []
            var remainingEvidenceArtifactsKnown = true
            #if os(macOS)
                do {
                    let deletion = try LocalEvidence(root: root).deleteOwnedData()
                    removedEvidenceArtifacts = deletion.removedArtifactURLs
                } catch let error as LocalEvidenceDeletionError {
                    removedEvidenceArtifacts = error.removedArtifactURLs
                    remainingEvidenceArtifacts = error.remainingArtifactURLs
                    remainingEvidenceArtifactsKnown = error.remainingArtifactsKnown
                    failureReasons.append(error.reason)
                } catch {
                    remainingEvidenceArtifactsKnown = false
                    failureReasons.append(
                        "Evidence deletion could not be completed: \(error.localizedDescription)"
                    )
                }
            #endif

            if !remainingRecoveryArtifactsKnown || !remainingEvidenceArtifactsKnown
                || !remainingRecoveryArtifacts.isEmpty || !remainingEvidenceArtifacts.isEmpty
            {
                throw StoreDataDeletionError(
                    removedRecoveryArtifactURLs: removedRecoveryArtifacts,
                    remainingRecoveryArtifactURLs: remainingRecoveryArtifacts,
                    removedQuarantineURLs: removedRecoveryArtifacts.filter(Self.isStoreOwnedQuarantine),
                    remainingQuarantineURLs: remainingRecoveryArtifacts.filter(Self.isStoreOwnedQuarantine),
                    remainingRecoveryArtifactsKnown: remainingRecoveryArtifactsKnown,
                    removedEvidenceArtifactURLs: removedEvidenceArtifacts,
                    remainingEvidenceArtifactURLs: remainingEvidenceArtifacts,
                    remainingEvidenceArtifactsKnown: remainingEvidenceArtifactsKnown,
                    reason: failureReasons.joined(separator: "; ")
                )
            }
            return StoreDeletionResult(
                worldURL: worldURL,
                deletedAt: Date(),
                removedRecoveryArtifactURLs: removedRecoveryArtifacts,
                removedQuarantineURLs: removedRecoveryArtifacts.filter(Self.isStoreOwnedQuarantine),
                removedEvidenceArtifactURLs: removedEvidenceArtifacts
            )
        }
    }

    public var worldURL: URL {
        root.appendingPathComponent("world.json")
    }

    private var lockURL: URL {
        root.appendingPathComponent("world.lock")
    }

    private func readWorldData() throws -> Data? {
        let fd = open(worldURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP {
                throw StoreError.unsafeWorldTarget("world.json must not be a symbolic link")
            }
            throw StoreError.cannotOpenWorld(Self.posixMessage())
        }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw StoreError.cannotInspectWorld(Self.posixMessage())
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw StoreError.unsafeWorldTarget("world.json must be a regular file")
        }
        guard info.st_size >= 0 else {
            throw StoreError.unsafeWorldTarget("world.json reported a negative size")
        }
        guard info.st_size <= WorldPersistenceLimits.maximumFileBytes else {
            throw StoreError.worldTooLarge(
                actualBytes: info.st_size,
                maximumBytes: WorldPersistenceLimits.maximumFileBytes
            )
        }

        let maximum = Int(WorldPersistenceLimits.maximumFileBytes)
        var data = Data()
        data.reserveCapacity(min(Int(info.st_size), maximum))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let amount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fd, bytes.baseAddress, min(bytes.count, maximum + 1 - data.count))
            }
            if amount == 0 { break }
            if amount < 0 {
                if errno == EINTR { continue }
                throw StoreError.cannotReadWorld(Self.posixMessage())
            }
            data.append(contentsOf: buffer.prefix(amount))
            if data.count > maximum {
                throw StoreError.worldTooLarge(
                    actualBytes: Int64(data.count),
                    maximumBytes: WorldPersistenceLimits.maximumFileBytes
                )
            }
        }
        return data
    }

    private func saveUnlocked(_ world: World) throws {
        try world.validateForPersistence()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try rejectUnsafeExistingWorldTarget()
        let data = try JSONEncoder.flowmo.encode(world)
        try enforceEncodedSize(data)
        try atomicWrite(data, to: worldURL)
    }

    /// Recheck the destination while holding its lock. A concurrently repaired
    /// valid destination wins; an invalid one is preserved before replacement.
    private func installMigratedWorldIfNeeded(_ world: World) throws -> Bool {
        try withLock {
            var info = stat()
            if lstat(worldURL.path, &info) == 0 {
                do {
                    _ = try load()
                    return false
                } catch {
                    _ = try quarantineInvalidWorldAndReplace(
                        with: world,
                        invalidReason: error.localizedDescription
                    )
                    _ = try load()
                    return true
                }
            }
            guard errno == ENOENT else {
                throw StoreError.cannotInspectWorld(Self.posixMessage())
            }
            try saveUnlocked(world)
            _ = try load()
            return true
        }
    }

    /// Caller holds `world.lock`. The replacement is one atomic rename; the
    /// quarantine remains if and only if replacement succeeds.
    private func quarantineInvalidWorldAndReplace(
        with replacement: World,
        invalidReason: String
    ) throws -> QuarantinedWorld {
        var info = stat()
        guard lstat(worldURL.path, &info) == 0 else {
            if errno == ENOENT { throw StoreError.worldMissing }
            throw StoreError.cannotInspectWorld(Self.posixMessage())
        }

        let quarantinedAt = Date()
        let quarantineURL = root.appendingPathComponent(
            "\(Self.quarantinePrefix)\(UUID().uuidString).json"
        )
        let isRegular = (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)

        if isRegular {
            guard link(worldURL.path, quarantineURL.path) == 0 else {
                throw StoreError.cannotQuarantine(Self.posixMessage())
            }
            do {
                try saveUnlocked(replacement)
            } catch {
                _ = unlink(quarantineURL.path)
                throw error
            }
        } else {
            guard rename(worldURL.path, quarantineURL.path) == 0 else {
                throw StoreError.cannotQuarantine(Self.posixMessage())
            }
            do {
                try saveUnlocked(replacement)
            } catch {
                _ = rename(quarantineURL.path, worldURL.path)
                throw error
            }
        }

        return QuarantinedWorld(
            originalURL: worldURL,
            quarantineURL: quarantineURL,
            quarantinedAt: quarantinedAt,
            originalByteCount: isRegular ? info.st_size : nil,
            invalidReason: invalidReason
        )
    }

    private func enforceEncodedSize(_ data: Data) throws {
        guard Int64(data.count) <= WorldPersistenceLimits.maximumFileBytes else {
            throw StoreError.worldTooLarge(
                actualBytes: Int64(data.count),
                maximumBytes: WorldPersistenceLimits.maximumFileBytes
            )
        }
    }

    private func rejectUnsafeExistingWorldTarget() throws {
        var info = stat()
        if lstat(worldURL.path, &info) == 0 {
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                throw StoreError.unsafeWorldTarget("world.json must be a regular file")
            }
            return
        }
        guard errno == ENOENT else {
            throw StoreError.cannotInspectWorld(Self.posixMessage())
        }
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = root.appendingPathComponent("\(Self.temporaryWritePrefix)\(UUID().uuidString).tmp")
        let fd = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard fd >= 0 else { throw StoreError.cannotWriteWorld(Self.posixMessage()) }
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
                    throw StoreError.cannotWriteWorld(Self.posixMessage())
                }
                guard amount > 0 else {
                    throw StoreError.cannotWriteWorld("write returned zero bytes")
                }
                offset += amount
            }
        }
        guard fsync(fd) == 0 else { throw StoreError.cannotWriteWorld(Self.posixMessage()) }
        guard rename(temporary.path, destination.path) == 0 else {
            throw StoreError.cannotWriteWorld(Self.posixMessage())
        }
        keepTemporary = false
    }

    private func quarantineURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter(Self.isStoreOwnedQuarantine)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func recoveryArtifactURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        )
        .filter { Self.isStoreOwnedQuarantine($0) || Self.isStoreOwnedTemporaryWrite($0) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isStoreOwnedQuarantine(_ url: URL) -> Bool {
        hasExactUUIDName(url.lastPathComponent, prefix: quarantinePrefix, suffix: ".json")
    }

    private static func isStoreOwnedTemporaryWrite(_ url: URL) -> Bool {
        hasExactUUIDName(url.lastPathComponent, prefix: temporaryWritePrefix, suffix: ".tmp")
    }

    private static func hasExactUUIDName(_ name: String, prefix: String, suffix: String) -> Bool {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        let tokenStart = name.index(name.startIndex, offsetBy: prefix.count)
        let tokenEnd = name.index(name.endIndex, offsetBy: -suffix.count)
        guard tokenStart < tokenEnd else { return false }
        return UUID(uuidString: String(name[tokenStart..<tokenEnd])) != nil
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = lockURL.path
        let fd = open(
            path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard fd >= 0 else {
            throw StoreError.lockFailed(Self.posixMessage())
        }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            close(fd)
            throw StoreError.lockFailed("world.lock must be a regular file")
        }
        let locked = flock(fd, LOCK_EX)
        defer {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }
        guard locked == 0 else { throw StoreError.lockFailed(Self.posixMessage()) }
        return try body()
    }

    private static func posixMessage() -> String {
        String(cString: strerror(errno))
    }
}

public struct QuarantinedWorld: Equatable, Sendable {
    public let originalURL: URL
    public let quarantineURL: URL
    public let quarantinedAt: Date
    public let originalByteCount: Int64?
    public let invalidReason: String
}

public struct StoreResetResult: Equatable, Sendable {
    public let worldURL: URL
    public let resetAt: Date
    public let preservedQuarantineURLs: [URL]
}

public struct StoreDeletionResult: Equatable, Sendable {
    public let worldURL: URL
    public let deletedAt: Date
    public let removedRecoveryArtifactURLs: [URL]
    public let removedQuarantineURLs: [URL]
    public let removedEvidenceArtifactURLs: [URL]

    public var removedRecoveryArtifactCount: Int { removedRecoveryArtifactURLs.count }
    public var removedQuarantineCount: Int { removedQuarantineURLs.count }
    public var removedEvidenceArtifactCount: Int { removedEvidenceArtifactURLs.count }
}

public struct StoreDataDeletionError: LocalizedError, Equatable, Sendable {
    public let removedRecoveryArtifactURLs: [URL]
    public let remainingRecoveryArtifactURLs: [URL]
    public let removedQuarantineURLs: [URL]
    public let remainingQuarantineURLs: [URL]
    public let remainingRecoveryArtifactsKnown: Bool
    public let removedEvidenceArtifactURLs: [URL]
    public let remainingEvidenceArtifactURLs: [URL]
    public let remainingEvidenceArtifactsKnown: Bool
    public let reason: String

    public var removedRecoveryArtifactCount: Int { removedRecoveryArtifactURLs.count }
    public var remainingRecoveryArtifactCount: Int { remainingRecoveryArtifactURLs.count }
    public var removedQuarantineCount: Int { removedQuarantineURLs.count }
    public var removedEvidenceArtifactCount: Int { removedEvidenceArtifactURLs.count }
    public var remainingEvidenceArtifactCount: Int { remainingEvidenceArtifactURLs.count }

    public var errorDescription: String? {
        if remainingRecoveryArtifactsKnown, remainingEvidenceArtifactsKnown {
            let remainingCount = remainingRecoveryArtifactCount + remainingEvidenceArtifactCount
            return
                "Flowmo data was reset, but \(remainingCount) owned data artifacts remain: \(reason)."
        }
        return "Flowmo data was reset, but owned-data cleanup could not be verified: \(reason)."
    }
}

public enum StoreError: LocalizedError, Equatable, Sendable {
    case lockFailed(String)
    case cannotOpenWorld(String)
    case cannotInspectWorld(String)
    case cannotReadWorld(String)
    case cannotDecodeWorld(String)
    case cannotWriteWorld(String)
    case cannotQuarantine(String)
    case unsafeWorldTarget(String)
    case worldTooLarge(actualBytes: Int64, maximumBytes: Int64)
    case worldIsValid
    case worldMissing
    case liveSessionPreventsReset

    public var errorDescription: String? {
        switch self {
        case .lockFailed(let reason): return "Could not lock the Flowmo store: \(reason)."
        case .cannotOpenWorld(let reason): return "Could not open world.json: \(reason)."
        case .cannotInspectWorld(let reason): return "Could not inspect world.json: \(reason)."
        case .cannotReadWorld(let reason): return "Could not read world.json: \(reason)."
        case .cannotDecodeWorld(let reason): return "Could not decode world.json: \(reason)."
        case .cannotWriteWorld(let reason): return "Could not write world.json: \(reason)."
        case .cannotQuarantine(let reason): return "Could not preserve invalid world.json: \(reason)."
        case .unsafeWorldTarget(let reason): return "Unsafe Flowmo store target: \(reason)."
        case .worldTooLarge(let actual, let maximum):
            return "world.json is \(actual) bytes; maximum allowed size is \(maximum) bytes."
        case .worldIsValid: return "world.json is valid and does not need quarantine."
        case .worldMissing: return "world.json disappeared before it could be quarantined."
        case .liveSessionPreventsReset: return "End the live session before resetting Flowmo data."
        }
    }
}

enum FlowmoJSON {
    static func stamp() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func stampFallback() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

extension JSONEncoder {
    public static var flowmo: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(FlowmoJSON.stamp().string(from: date))
        }
        return encoder
    }
}

extension JSONDecoder {
    public static var flowmo: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = FlowmoJSON.stamp().date(from: raw) ?? FlowmoJSON.stampFallback().date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(raw)")
        }
        return decoder
    }
}
