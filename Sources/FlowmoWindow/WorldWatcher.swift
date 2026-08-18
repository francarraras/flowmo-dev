import Darwin
import Foundation

final class WorldWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: DispatchQueue.main
        )
        src.setEventHandler { [onChange] in
            onChange()
        }
        src.setCancelHandler {
            close(fd)
        }
        src.resume()
        source = src
    }

    deinit {
        source?.cancel()
        source = nil
    }
}
