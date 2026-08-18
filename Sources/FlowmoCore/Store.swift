import Darwin
import Foundation

public struct Store: Sendable {
    public let root: URL

    public static var `default`: Store {
        if let override = ProcessInfo.processInfo.environment["FLOWMO_HOME"], !override.isEmpty {
            return Store(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        let home = ProcessInfo.processInfo.environment["HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser
        return Store(root: home.appendingPathComponent(".flowmo", isDirectory: true))
    }

    public init(root: URL) {
        self.root = root
    }

    public func load() throws -> World {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = worldURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.flowmo.decode(World.self, from: data)
    }

    public func save(_ world: World) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder.flowmo.encode(world)
        try data.write(to: worldURL, options: .atomic)
    }

    public func update(_ body: (inout Engine) throws -> Void) throws -> Engine {
        try withLock {
            var engine = Engine(world: try load())
            let before = engine.world
            try body(&engine)
            if engine.world != before {
                try save(engine.world)
            }
            return engine
        }
    }

    public var worldURL: URL {
        root.appendingPathComponent("world.json")
    }

    private var lockURL: URL {
        root.appendingPathComponent("world.lock")
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = lockURL.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: Data())
        }
        let fd = open(path, O_RDWR)
        guard fd >= 0 else {
            throw StoreError.lockFailed
        }
        let locked = flock(fd, LOCK_EX)
        defer {
            _ = flock(fd, LOCK_UN)
            close(fd)
        }
        guard locked == 0 else { throw StoreError.lockFailed }
        return try body()
    }
}

public enum StoreError: Error {
    case lockFailed
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

public extension JSONEncoder {
    static var flowmo: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(FlowmoJSON.stamp().string(from: date))
        }
        return encoder
    }
}

public extension JSONDecoder {
    static var flowmo: JSONDecoder {
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
