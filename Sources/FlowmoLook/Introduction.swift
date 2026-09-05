import Foundation
import SwiftUI

/// Device-local presentation preference. Tutorial actions never touch a session.
@MainActor
public final class IntroductionState: ObservableObject {
    public static let completionKey = "FlowmoIntroductionVersion"
    public static let currentVersion = 1

    @Published public private(set) var isPresented = false
    @Published public private(set) var page = 0
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var hasCompleted: Bool {
        userDefaults.integer(forKey: Self.completionKey) >= Self.currentVersion
    }

    public func presentIfNeeded(canPresent: Bool) {
        guard canPresent else {
            isPresented = false
            return
        }
        guard !hasCompleted, !isPresented else { return }
        page = 0
        isPresented = true
    }

    public func replay(canPresent: Bool) {
        guard canPresent else { return }
        page = 0
        isPresented = true
    }

    public func next() {
        guard isPresented else { return }
        page = min(page + 1, 2)
    }

    public func back() {
        guard isPresented else { return }
        page = max(page - 1, 0)
    }

    /// Skip and completion both dismiss this version permanently; replay remains available.
    public func finish() {
        guard isPresented else { return }
        userDefaults.set(Self.currentVersion, forKey: Self.completionKey)
        isPresented = false
        page = 0
    }
}

public struct IntroductionView: View {
    @ObservedObject private var state: IntroductionState
    @Environment(\.atmosphere) private var atmo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var requestedNotifications = false
    private let onRequestNotifications: () -> Void

    public init(state: IntroductionState, onRequestNotifications: @escaping () -> Void) {
        self.state = state
        self.onRequestNotifications = onRequestNotifications
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How it works · \(state.page + 1) of 3")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(atmo.mute)
                Spacer(minLength: 8)
                QuietButton("Skip", minHeight: 44) { state.finish() }
            }

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Spacer(minLength: 0)
                        Image(systemName: symbol)
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Atmosphere.rest)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(title)
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .foregroundStyle(atmo.ink)
                                .accessibilityAddTraits(.isHeader)
                            Text(explanation)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(atmo.mute)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detail)
                                .font(.system(.callout, design: .rounded).weight(.medium))
                                .foregroundStyle(Atmosphere.rest)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id(state.page)
                        .transition(.opacity)
                        Spacer(minLength: 0)
                        if state.page == 2 {
                            notificationChoice
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            HStack(spacing: 12) {
                if state.page > 0 {
                    QuietButton("Back", minHeight: 44) { state.back() }
                }
                Spacer(minLength: 0)
                InkButton(state.page == 2 ? "Set intention" : "Continue") {
                    if state.page == 2 {
                        state.finish()
                    } else {
                        state.next()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : Motion.phase, value: state.page)
    }

    private var notificationChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !requestedNotifications {
                QuietButton("Enable notifications", minHeight: 44) {
                    requestedNotifications = true
                    onRequestNotifications()
                }
            }
            Text(
                requestedNotifications
                    ? "You can change alerts later in system settings."
                    : "Optional alerts tell you when preparation or a break ends."
            )
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(atmo.mute)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var symbol: String {
        switch state.page {
        case 0: "pencil.line"
        case 1: "arrow.up.right"
        default: "sun.horizon"
        }
    }

    private var title: String {
        switch state.page {
        case 0: "One intention. A little space."
        case 1: "Your pace sets the clock."
        default: "Rest, then leave a next step."
        }
    }

    private var explanation: String {
        switch state.page {
        case 0:
            "Write what you want to work on. Take up to two minutes to settle, or choose Focus now whenever you’re ready."
        case 1:
            "Focus counts up. Work until you choose to stop. Park a passing thought without leaving your session."
        default:
            "Your break grows with your Focus. After resting, an optional reflection helps you choose where to pick up next."
        }
    }

    private var detail: String {
        switch state.page {
        case 0: "You only type your intention once."
        case 1: "No deadline. No race to finish."
        default: "By default, 50 minutes of Focus earns 10 minutes of rest."
        }
    }
}
