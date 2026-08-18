import AppKit
import FlowmoCore
import UserNotifications

@MainActor
public final class AttentionAdapter: NSObject, UNUserNotificationCenterDelegate {
    weak var window: NSWindow?
    private let usesUserNotifications: Bool
    private let legacy = LegacyNotifier()

    public override init() {
        usesUserNotifications = Self.hasNotificationBundle
        super.init()
        if usesUserNotifications {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        } else {
            legacy.onActivate = { [weak self] in
                Task { @MainActor in
                    self?.bringWindowForward()
                }
            }
            legacy.install()
        }
    }

    func phaseChanged(from: SessionPhase?, to: SessionPhase?) {
        guard AttentionCue.shouldPlay(from: from, to: to) else { return }
        playCue()
        if windowIsInBackground {
            postNotification(phase: to)
        }
    }

    func bringWindowForward() {
        NSApp.unhide(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static var hasNotificationBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private var windowIsInBackground: Bool {
        guard let window else { return true }
        if !window.isVisible { return true }
        if !NSApp.isActive { return true }
        if !window.isKeyWindow { return true }
        return false
    }

    private func playCue() {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func postNotification(phase: SessionPhase?) {
        let (title, body) = Self.copy(for: phase)
        if usesUserNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: "flowmo.phase", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        } else {
            legacy.deliver(title: title, body: body)
        }
    }

    private static func copy(for phase: SessionPhase?) -> (String, String) {
        switch phase {
        case .focus:
            return ("Flowmo", "Prime ended.")
        case .onBreak:
            return ("Flowmo", "Focus stopped. Break earned.")
        case .recall:
            return ("Flowmo", "Break ended.")
        case .closeBeat:
            return ("Flowmo", "Recall ended.")
        default:
            return ("Flowmo", "Phase changed.")
        }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.bringWindowForward()
        }
        completionHandler()
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

/// Used when `swift run` has no bundle identifier (UNUserNotificationCenter crashes).
private final class LegacyNotifier: NSObject, @unchecked Sendable {
    var onActivate: (@Sendable () -> Void)?

    func install() {
        NSUserNotificationCenter.default.delegate = self
    }

    func deliver(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = nil
        NSUserNotificationCenter.default.deliver(notification)
    }
}

extension LegacyNotifier: NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        onActivate?()
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        true
    }
}
