import AudioToolbox
import Foundation
import FlowmoCore
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class PhoneAttention: NSObject, UNUserNotificationCenterDelegate {
    public static let requestID = "flowmo.timed-phase"

    public override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    public func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func phaseChanged(from: SessionPhase?, to: SessionPhase?, cuesEnabled: Bool) {
        guard AttentionCue.shouldPlay(from: from, to: to) else { return }
        guard cuesEnabled else { return }
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else { return }
        #endif
        AudioServicesPlaySystemSound(1104)
    }

    func reconcile(status: SessionStatus, cuesEnabled: Bool) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        guard let delay = TimedNotice.remainingToSchedule(status) else { return }
        let next: SessionPhase
        switch status.phase {
        case .prime: next = .focus
        case .onBreak: next = .recall
        case .recall: next = .closeBeat
        default: return
        }
        let copy = TimedNotice.copy(for: next)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        if cuesEnabled {
            content.sound = .default
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
