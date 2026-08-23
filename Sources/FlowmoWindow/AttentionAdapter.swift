import AppKit
import FlowmoCore
import UserNotifications

@MainActor
public final class AttentionAdapter: NSObject, UNUserNotificationCenterDelegate {
    weak var window: NSWindow?
    private let canNotify: Bool

    public override convenience init() {
        self.init(canNotify: Bundle.main.bundleIdentifier != nil)
    }

    init(canNotify: Bool) {
        self.canNotify = canNotify
        super.init()
        guard canNotify else { return }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func phaseChanged(from: SessionPhase?, to: SessionPhase?, cuesEnabled: Bool) {
        guard AttentionCue.shouldPlay(from: from, to: to) else { return }
        if cuesEnabled {
            playCue()
        }
        if windowIsInBackground {
            postNotification(phase: to)
        }
    }

    func bringWindowForward() {
        NSApp.unhide(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        guard canNotify else { return }
        let (title, body) = Self.copy(for: phase)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "flowmo.phase", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func copy(for phase: SessionPhase?) -> (String, String) {
        TimedNotice.copy(for: phase)
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
