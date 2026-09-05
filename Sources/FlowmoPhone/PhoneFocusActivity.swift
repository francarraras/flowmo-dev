import FlowmoActivity
import Foundation

struct PhoneFocusActivitySnapshot: Equatable, Sendable {
    let id: String
    let projection: FocusActivityProjection
    var isActive = true
}

@MainActor
protocol PhoneFocusActivityClient: AnyObject {
    var activities: [PhoneFocusActivitySnapshot] { get }
    var activitiesEnabled: Bool { get }
    var applicationIsActive: Bool { get }
    func request(_ projection: FocusActivityProjection) throws -> PhoneFocusActivitySnapshot
    func update(_ activity: PhoneFocusActivitySnapshot, to projection: FocusActivityProjection) async
    func end(_ activity: PhoneFocusActivitySnapshot) async
}

/// Serializes the disposable system glance; it never mutates a session or its clock.
@MainActor
public final class PhoneFocusActivityCoordinator {
    private static let sessionKey = "FlowmoFocusLiveActivitySession"
    private static let activityKey = "FlowmoFocusLiveActivityID"
    private static let dismissedKey = "FlowmoFocusLiveActivityDismissedSession"

    private let client: any PhoneFocusActivityClient
    private let defaults: UserDefaults
    private var desired: FocusActivityProjection?
    private var canStart = false
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var failedSessionID: UUID?

    public convenience init(userDefaults: UserDefaults = .standard) {
        #if os(iOS)
            self.init(client: NativePhoneFocusActivityClient(), userDefaults: userDefaults)
        #else
            self.init(client: UnavailablePhoneFocusActivityClient(), userDefaults: userDefaults)
        #endif
    }

    init(client: any PhoneFocusActivityClient, userDefaults: UserDefaults) {
        self.client = client
        self.defaults = userDefaults
    }

    public func reconcile(_ projection: FocusActivityProjection?, canStart: Bool) {
        desired = projection
        self.canStart = canStart
        revision += 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true {
                let currentRevision = revision
                await applyDesiredState(revision: currentRevision)
                if currentRevision == revision { break }
            }
            worker = nil
        }
    }

    public func endAndForget() {
        clearTrackedActivity()
        defaults.removeObject(forKey: Self.dismissedKey)
        failedSessionID = nil
        reconcile(nil, canStart: false)
    }

    func waitForPendingReconciliation() async {
        await worker?.value
    }

    private func applyDesiredState(revision expectedRevision: Int) async {
        let activities = client.activities
        if let previousID = defaults.string(forKey: Self.activityKey),
            let previousSession = defaults.string(forKey: Self.sessionKey),
            !activities.contains(where: { $0.id == previousID && $0.isActive })
        {
            // A person or the system removed the glance. Don't recreate it for this session,
            // including after a process relaunch. No session text enters preferences.
            defaults.set(previousSession, forKey: Self.dismissedKey)
            clearTrackedActivity()
        }

        let projection = desired
        let matching = activities.first { $0.isActive && $0.projection.sessionID == projection?.sessionID }
        for activity in activities where activity.id != matching?.id {
            clearTrackedActivity(ifMatching: activity.id)
            await client.end(activity)
            guard revision == expectedRevision else { return }
        }
        guard let projection else { return }

        if let matching {
            track(matching)
            if matching.projection != projection {
                await client.update(matching, to: projection)
            }
            return
        }

        guard revision == expectedRevision,
            canStart,
            client.applicationIsActive,
            client.activitiesEnabled,
            defaults.string(forKey: Self.dismissedKey) != projection.sessionID.uuidString,
            failedSessionID != projection.sessionID
        else { return }

        do {
            track(try client.request(projection))
        } catch {
            // An optional glance must never block Start, Continue, or persistence.
            // Avoid retrying a denied request on every capture in the same Focus.
            failedSessionID = projection.sessionID
        }
    }

    private func track(_ activity: PhoneFocusActivitySnapshot) {
        defaults.set(activity.projection.sessionID.uuidString, forKey: Self.sessionKey)
        defaults.set(activity.id, forKey: Self.activityKey)
    }

    private func clearTrackedActivity(ifMatching id: String? = nil) {
        if let id, defaults.string(forKey: Self.activityKey) != id { return }
        defaults.removeObject(forKey: Self.sessionKey)
        defaults.removeObject(forKey: Self.activityKey)
    }
}

#if os(iOS)
    import ActivityKit
    import UIKit

    @MainActor
    private final class NativePhoneFocusActivityClient: PhoneFocusActivityClient {
        var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
        var applicationIsActive: Bool { UIApplication.shared.applicationState == .active }

        var activities: [PhoneFocusActivitySnapshot] {
            Activity<FocusActivityAttributes>.activities.compactMap { activity in
                guard activity.activityState != .dismissed else { return nil }
                return snapshot(activity)
            }
        }

        func request(_ projection: FocusActivityProjection) throws -> PhoneFocusActivitySnapshot {
            let activity = try Activity<FocusActivityAttributes>.request(
                attributes: FocusActivityAttributes(sessionID: projection.sessionID),
                content: ActivityContent(
                    state: FocusActivityAttributes.ContentState(startedAt: projection.startedAt),
                    staleDate: nil
                ),
                pushType: nil
            )
            return snapshot(activity)
        }

        func update(_ activity: PhoneFocusActivitySnapshot, to projection: FocusActivityProjection) async {
            await Self.updateActivity(id: activity.id, to: projection)
        }

        func end(_ activity: PhoneFocusActivitySnapshot) async {
            await Self.endActivity(id: activity.id)
        }

        // ActivityKit's Activity is not Sendable. Resolve and consume it on the
        // same nonisolated async executor; only immutable snapshots cross actors.
        nonisolated private static func updateActivity(id: String, to projection: FocusActivityProjection) async {
            guard let live = Activity<FocusActivityAttributes>.activities.first(where: { $0.id == id }) else {
                return
            }
            await live.update(
                ActivityContent(
                    state: FocusActivityAttributes.ContentState(startedAt: projection.startedAt),
                    staleDate: nil
                )
            )
        }

        nonisolated private static func endActivity(id: String) async {
            guard let live = Activity<FocusActivityAttributes>.activities.first(where: { $0.id == id }) else {
                return
            }
            await live.end(nil, dismissalPolicy: .immediate)
        }

        private func snapshot(_ activity: Activity<FocusActivityAttributes>) -> PhoneFocusActivitySnapshot {
            PhoneFocusActivitySnapshot(
                id: activity.id,
                projection: FocusActivityProjection(
                    sessionID: activity.attributes.sessionID,
                    startedAt: activity.content.state.startedAt
                ),
                isActive: activity.activityState == .active || activity.activityState == .stale
            )
        }
    }
#else
    @MainActor
    private final class UnavailablePhoneFocusActivityClient: PhoneFocusActivityClient {
        var activities: [PhoneFocusActivitySnapshot] { [] }
        var activitiesEnabled: Bool { false }
        var applicationIsActive: Bool { false }
        func request(_ projection: FocusActivityProjection) throws -> PhoneFocusActivitySnapshot {
            throw CocoaError(.featureUnsupported)
        }
        func update(_ activity: PhoneFocusActivitySnapshot, to projection: FocusActivityProjection) async {}
        func end(_ activity: PhoneFocusActivitySnapshot) async {}
    }
#endif
