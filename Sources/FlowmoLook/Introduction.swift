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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var requestedNotifications = false
    private let onRequestNotifications: () -> Void

    public init(state: IntroductionState, onRequestNotifications: @escaping () -> Void) {
        self.state = state
        self.onRequestNotifications = onRequestNotifications
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Flowmo")
                        .font(.system(.headline).weight(.medium))
                        .tracking(-0.4)
                        .foregroundStyle(atmo.ink)
                        .accessibilityLabel("Flowmo. How it works")
                    HStack(spacing: 5) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .fill(index <= state.page ? atmo.ink : atmo.track)
                                .frame(width: index == state.page ? 24 : 8, height: 3)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(state.page + 1) of 3")
                }
                Spacer(minLength: 12)
                QuietButton("Skip", minHeight: 44) { state.finish() }
            }

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        illustration
                            .frame(height: artworkHeight(available: geometry.size.height))
                        VStack(alignment: .leading, spacing: 12) {
                            Text(title)
                                .font(headlineFont)
                                .tracking(-0.65)
                                .foregroundStyle(atmo.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            Text(explanation)
                                .font(.system(.body))
                                .lineSpacing(3)
                                .foregroundStyle(atmo.mute)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detail)
                                .font(.system(.callout).weight(.medium))
                                .foregroundStyle(state.page == 2 ? Atmosphere.rest : atmo.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                        .id(state.page)
                        .transition(.opacity)
                        if state.page == 2 {
                            notificationChoice
                        }
                    }
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .id(state.page)
            }

            footer
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : Motion.phase, value: state.page)
    }

    @ViewBuilder
    private var footer: some View {
        #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                verticalFooter
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalFooter
                    verticalFooter
                }
            }
        #else
            horizontalFooter
        #endif
    }

    private var horizontalFooter: some View {
        HStack(spacing: 12) {
            if state.page > 0 {
                QuietButton("Back", minHeight: 44) { state.back() }
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
            primaryAction
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var verticalFooter: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if state.page > 0 {
                QuietButton("Back", minHeight: 44) { state.back() }
            }
            primaryAction
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var primaryAction: some View {
        InkButton(state.page == 2 ? "Set intention" : "Continue") {
            if state.page == 2 {
                state.finish()
            } else {
                state.next()
            }
        }
        .keyboardShortcut(.defaultAction)
    }

    private var headlineFont: Font {
        #if os(iOS)
            .system(.title).weight(.medium)
        #else
            .system(.title2).weight(.medium)
        #endif
    }

    private func artworkHeight(available: CGFloat) -> CGFloat {
        let ideal = min(210, max(92, available * 0.34))
        return dynamicTypeSize.isAccessibilitySize ? min(112, ideal) : ideal
    }

    private var illustration: some View {
        GeometryReader { geometry in
            IntroductionArtwork.images[state.page]
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(Color(red: 0.035, green: 0.039, blue: 0.047))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(atmo.ink.opacity(0.09), lineWidth: 1)
                }
        }
        .accessibilityHidden(true)
    }

    private var notificationChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !requestedNotifications {
                QuietButton("Enable notifications", minHeight: 44) {
                    requestedNotifications = true
                    onRequestNotifications()
                }
            }
            Text(
                requestedNotifications
                    ? "You can change alerts later in system settings."
                    : "Optional alerts for the moments between Focus and rest."
            )
            .font(.system(.caption))
            .foregroundStyle(atmo.mute)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var title: String {
        switch state.page {
        case 0: "Make room for one thing."
        case 1: "Stay with the work."
        default: "Leave space to return."
        }
    }

    private var explanation: String {
        switch state.page {
        case 0:
            "Name what you’re here to do. Take up to two minutes to settle, or choose Focus now whenever you’re ready."
        case 1:
            "Your clock counts up for as long as you need. Park passing thoughts and keep going. You decide when Focus ends."
        default:
            "Take the break you’ve earned, then leave an optional next step. It will be waiting when you begin again."
        }
    }

    private var detail: String {
        switch state.page {
        case 0: "One intention, typed once."
        case 1: "No deadline. No finish line."
        default: "By default, 50 minutes focused earns 10 minutes of rest."
        }
    }
}
