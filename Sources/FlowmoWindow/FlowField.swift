import AppKit
import SwiftUI
import FlowmoLook

/// One-line instrument field with reliable focus.
///
/// Claims the caret after the phase spring. A single hairline marks the
/// slot; it brightens and blooms on focus. Return and Esc still work; verbs sit below.
struct FlowField: View {
    @Environment(\.atmosphere) private var atmo
    var placeholder: String
    @Binding var text: String
    var centered: Bool
    var autofocus: Bool
    var focusDelay: TimeInterval
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    @FocusState private var focused: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        centered: Bool = false,
        autofocus: Bool = false,
        focusDelay: TimeInterval = 0.12,
        onSubmit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.centered = centered
        self.autofocus = autofocus
        self.focusDelay = focusDelay
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.system(.body, design: .rounded).weight(.medium))
                .multilineTextAlignment(centered ? .center : .leading)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .onSubmit { onSubmit?() }
                .onExitCommand { onCancel?() }

            Rectangle()
                .fill(
                    focused
                        ? LinearGradient(
                            colors: [atmo.mute, atmo.ink.opacity(0.9), atmo.mute],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [atmo.faint.opacity(0.6), atmo.mute.opacity(0.55), atmo.faint.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
                .frame(height: 1)
                .padding(.horizontal, 8)
                .shadow(color: atmo.ink.opacity(focused ? 0.6 : 0), radius: 4, y: 2)
                .animation(Motion.tick, value: focused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture { focusSoon() }
        .onAppear { focusSoon() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if !focused {
                focusSoon()
            }
        }
    }

    private func focusSoon() {
        guard autofocus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
            focused = true
        }
    }
}
