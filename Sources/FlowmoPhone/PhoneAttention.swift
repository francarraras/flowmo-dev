import AudioToolbox
import FlowmoCore
import Foundation
import UserNotifications

#if canImport(UIKit)
    import UIKit
#endif

struct PhoneTimedNotification: Equatable, Sendable {
    let destination: SessionPhase
    let fireDate: Date

    var identifier: String { "flowmo.timed-phase.\(destination.rawValue)" }
}

/// Project every known timed boundary before suspension, without changing the store.
struct PhoneNotificationPlan: Equatable, Sendable {
    static let identifiersToCancel = [
        "flowmo.timed-phase",
        "flowmo.timed-phase.focus",
        "flowmo.timed-phase.recall",
        "flowmo.timed-phase.closeBeat",
    ]

    let notifications: [PhoneTimedNotification]

    init(world: World, now: Date) {
        var projected = Engine(world: world)
        projected.sync(now: now)
        var notifications: [PhoneTimedNotification] = []

        // Break -> Reflection -> Close Beat is the longest predictable chain.
        boundaries: for _ in 0..<2 {
            guard let live = projected.world.live, !live.isPaused else { break }
            let boundary: Date
            let destination: SessionPhase
            switch live.phase {
            case .prime:
                boundary = live.phaseStartedAt.addingTimeInterval(live.primeDuration)
                destination = .focus
            case .onBreak:
                guard let startedAt = live.breakStartedAt, let duration = live.breakDuration else { break boundaries }
                boundary = startedAt.addingTimeInterval(duration)
                destination = .recall
            case .recall:
                boundary = live.phaseStartedAt.addingTimeInterval(live.recallDuration)
                destination = .closeBeat
            case .focus, .closeBeat:
                self.notifications = notifications
                return
            }
            guard boundary > now else { break }
            notifications.append(PhoneTimedNotification(destination: destination, fireDate: boundary))
            projected.sync(now: boundary)
        }
        self.notifications = notifications
    }
}

@MainActor
protocol PhoneNotificationClient {
    func requestPermission()
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
private struct SystemPhoneNotificationClient: PhoneNotificationClient {
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
public final class PhoneAttention: NSObject, UNUserNotificationCenterDelegate {
    public static let requestID = "flowmo.timed-phase"
    private let client: (any PhoneNotificationClient)?
    private var reconciliationTask: Task<Void, Never>?

    public override init() {
        self.client = SystemPhoneNotificationClient()
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    init(notificationsEnabled: Bool) {
        self.client = notificationsEnabled ? SystemPhoneNotificationClient() : nil
        super.init()
        if notificationsEnabled {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    init(client: any PhoneNotificationClient) {
        self.client = client
        super.init()
    }

    public func requestPermission() {
        client?.requestPermission()
    }

    func phaseChanged(from: SessionPhase?, to: SessionPhase?, cuesEnabled: Bool) {
        guard AttentionCue.shouldPlay(from: from, to: to) else { return }
        guard cuesEnabled else { return }
        #if canImport(UIKit)
            guard UIApplication.shared.applicationState == .active else { return }
        #endif
        AudioServicesPlaySystemSound(1104)
    }

    func reconcile(world: World, now: Date) {
        guard let client else { return }
        let plan = PhoneNotificationPlan(world: world, now: now)
        let cuesEnabled = world.config.cuesEnabled
        let previous = reconciliationTask
        previous?.cancel()
        reconciliationTask = Task {
            // An in-flight add must finish before the newer plan cancels it.
            await previous?.value
            guard !Task.isCancelled else { return }
            client.removePendingNotificationRequests(withIdentifiers: PhoneNotificationPlan.identifiersToCancel)
            for notification in plan.notifications {
                guard !Task.isCancelled else { return }
                let delay = notification.fireDate.timeIntervalSinceNow
                guard delay > 0 else { continue }
                let copy = TimedNotice.copy(for: notification.destination)
                let content = UNMutableNotificationContent()
                content.title = copy.title
                content.body = copy.body
                if cuesEnabled {
                    content.sound = .default
                }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
                let request = UNNotificationRequest(
                    identifier: notification.identifier,
                    content: content,
                    trigger: trigger
                )
                try? await client.add(request)
            }
        }
    }

    func waitForPendingReconciliation() async {
        await reconciliationTask?.value
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
