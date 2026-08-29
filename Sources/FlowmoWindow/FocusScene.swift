import AppKit
import FlowmoCore
import Foundation

/// A single-session, process-local presentation snapshot. Focus Scene never
/// becomes session data: it temporarily replaces the normal Mac frame while
/// one exact Focus is running, then restores the person's saved presentation.
struct FocusScenePresentation: Equatable {
    let sessionID: UUID
    let previousDisplayMode: DisplayMode
    let previousPinned: Bool

    func remainsActive(in world: World) -> Bool {
        guard let live = world.live else { return false }
        return live.id == sessionID
            && live.phase == .focus
            && !live.isPaused
    }
}

/// Borderless windows are not key-capable by default. Focus Scene is still the
/// main Flowmo window, so its explicit End / Leave actions must remain usable.
final class SceneCapableWindow: NSWindow {
    var sceneCloseHandler: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        guard sceneCloseHandler?() != true else { return }
        super.performClose(sender)
    }
}

enum FocusSceneWindowDrag {
    static func origin(from start: NSPoint, translation: CGSize) -> NSPoint {
        NSPoint(
            x: start.x + translation.width,
            y: start.y - translation.height
        )
    }
}

/// Every AppKit property changed for the Scene is process-local and restored.
/// This deliberately stays outside DisplayMode and the persisted World.
struct FocusSceneWindowSnapshot {
    let title: String
    let frame: NSRect
    let styleMask: NSWindow.StyleMask
    let level: NSWindow.Level
    let contentMinSize: NSSize
    let contentMaxSize: NSSize
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarAppearsTransparent: Bool
    let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
    let isMovable: Bool
    let isMovableByWindowBackground: Bool
    let isOpaque: Bool
    let hasShadow: Bool
    let hidesOnDeactivate: Bool
    let backgroundColor: NSColor
}

/// Morphs the one existing Flowmo window into the selected Distant Horizon
/// presentation. It never creates another surface or a macOS full-screen Space.
@MainActor
final class FocusSceneWindowCoordinator {
    static let minimumContentSize = NSSize(width: 720, height: 480)
    private static let maximumContentSize = NSSize(width: 10_000, height: 10_000)

    private weak var window: NSWindow?
    private(set) var snapshot: FocusSceneWindowSnapshot?

    init(window: NSWindow) {
        self.window = window
    }

    var isPresented: Bool { snapshot != nil }

    func present() {
        guard snapshot == nil, let window else { return }
        snapshot = FocusSceneWindowSnapshot(
            title: window.title,
            frame: window.frame,
            styleMask: window.styleMask,
            level: window.level,
            contentMinSize: window.contentMinSize,
            contentMaxSize: window.contentMaxSize,
            titleVisibility: window.titleVisibility,
            titlebarAppearsTransparent: window.titlebarAppearsTransparent,
            titlebarSeparatorStyle: window.titlebarSeparatorStyle,
            isMovable: window.isMovable,
            isMovableByWindowBackground: window.isMovableByWindowBackground,
            isOpaque: window.isOpaque,
            hasShadow: window.hasShadow,
            hidesOnDeactivate: window.hidesOnDeactivate,
            backgroundColor: window.backgroundColor
        )

        window.contentMinSize = NSSize(width: 1, height: 1)
        window.contentMaxSize = Self.maximumContentSize
        window.styleMask = [.borderless, .resizable]
        window.title = "Flowmo Focus Scene"
        window.level = .normal
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.backgroundColor = NSColor(red: 9 / 255, green: 10 / 255, blue: 12 / 255, alpha: 1)
        if let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first {
            applySceneFrame(Self.initialFrame(in: screen.visibleFrame), visibleFrame: screen.visibleFrame)
        } else {
            window.contentMinSize = Self.minimumContentSize
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Keep the one movable Scene visible when its screen changes or disappears.
    /// Connecting another display never clones it or moves it by itself.
    func reflow() {
        guard snapshot != nil, let window else { return }
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        applySceneFrame(
            Self.clampedFrame(window.frame, within: screen.visibleFrame),
            visibleFrame: screen.visibleFrame
        )
    }

    static func initialFrame(in visibleFrame: NSRect) -> NSRect {
        let minimum = adaptiveMinimumContentSize(in: visibleFrame)
        let size = NSSize(
            width: min(1_440, max(minimum.width, visibleFrame.width * 0.88)),
            height: min(900, max(minimum.height, visibleFrame.height * 0.86))
        )
        return NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    static func clampedFrame(_ frame: NSRect, within visibleFrame: NSRect) -> NSRect {
        let minimum = adaptiveMinimumContentSize(in: visibleFrame)
        let size = NSSize(
            width: min(visibleFrame.width, max(minimum.width, frame.width)),
            height: min(visibleFrame.height, max(minimum.height, frame.height))
        )
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return NSRect(
            x: min(max(frame.minX, visibleFrame.minX), maximumX),
            y: min(max(frame.minY, visibleFrame.minY), maximumY),
            width: size.width,
            height: size.height
        )
    }

    private static func adaptiveMinimumContentSize(in visibleFrame: NSRect) -> NSSize {
        NSSize(
            width: min(minimumContentSize.width, visibleFrame.width),
            height: min(minimumContentSize.height, visibleFrame.height)
        )
    }

    private func applySceneFrame(_ frame: NSRect, visibleFrame: NSRect) {
        guard let window else { return }
        window.contentMinSize = NSSize(width: 1, height: 1)
        window.contentMaxSize = Self.maximumContentSize
        window.setFrame(frame, display: true, animate: false)
        window.contentMinSize = Self.adaptiveMinimumContentSize(in: visibleFrame)
        window.contentMaxSize = visibleFrame.size
    }

    func restore() {
        guard let snapshot, let window else {
            self.snapshot = nil
            return
        }
        self.snapshot = nil

        window.contentMinSize = NSSize(width: 1, height: 1)
        window.contentMaxSize = Self.maximumContentSize
        window.styleMask = snapshot.styleMask
        window.title = snapshot.title
        window.setFrame(snapshot.frame, display: true, animate: false)
        window.level = snapshot.level
        window.titleVisibility = snapshot.titleVisibility
        window.titlebarAppearsTransparent = snapshot.titlebarAppearsTransparent
        window.titlebarSeparatorStyle = snapshot.titlebarSeparatorStyle
        window.isMovable = snapshot.isMovable
        window.isMovableByWindowBackground = snapshot.isMovableByWindowBackground
        window.isOpaque = snapshot.isOpaque
        window.hasShadow = snapshot.hasShadow
        window.hidesOnDeactivate = snapshot.hidesOnDeactivate
        window.backgroundColor = snapshot.backgroundColor
        window.contentMinSize = snapshot.contentMinSize
        window.contentMaxSize = snapshot.contentMaxSize
    }
}
