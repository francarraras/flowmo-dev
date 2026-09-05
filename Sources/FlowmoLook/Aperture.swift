import FlowmoCore
import SwiftUI

/// Ring mode. Standalone so Mini and Classic share one type.
public enum ApertureRing: Equatable {
    case none
    case idle
    case timed(progress: Double, rest: Bool = false, race: Bool = false)
}

/// The instrument. A circle that does not move. Phase is what it holds.
public struct Aperture<Content: View>: View {
    public typealias Ring = ApertureRing

    var ring: ApertureRing
    var contentPadding: CGFloat
    var content: Content

    public init(
        ring: Ring = .idle,
        contentPadding: CGFloat = 22,
        @ViewBuilder content: () -> Content
    ) {
        self.ring = ring
        self.contentPadding = contentPadding
        self.content = content()
    }

    @Environment(\.atmosphere) private var atmo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let diameter = min(side, max(96, side * 0.92))
            ZStack {
                well
                ringView
                content.padding(contentPadding)
                    .modifier(ApertureSettle())
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var well: some View {
        Circle()
            .fill(atmo.field)
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [atmo.ink.opacity(0.025), .clear],
                            center: UnitPoint(x: 0.5, y: 0.24),
                            startRadius: 0,
                            endRadius: 160
                        )
                    )
            }
            .overlay {
                Circle()
                    .strokeBorder(atmo.ink.opacity(0.055), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var ringView: some View {
        switch ring {
        case .none:
            EmptyView()
        case .idle:
            ApertureTrack(progress: nil, rest: false)
        case .timed(let progress, let rest, _):
            ApertureTrack(progress: progress, rest: rest)
        }
    }
}

/// One continuous track. The face and its contents never change size.
private struct ApertureTrack: View {
    let progress: Double?
    let rest: Bool

    @Environment(\.atmosphere) private var atmo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(atmo.track, lineWidth: 2)
            if let progress {
                Circle()
                    .inset(by: 1)
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(
                        rest ? Atmosphere.rest : atmo.ink,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.2), value: progress)
            }
        }
        .modifier(ApertureSettle())
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct ApertureSettle: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || settled ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    settled = true
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { settled = true }
                }
            }
    }
}

extension Aperture where Content == EmptyView {
    public init(ring: Ring, contentPadding: CGFloat = 22) {
        self.init(ring: ring, contentPadding: contentPadding) { EmptyView() }
    }
}

public struct InstrumentClock: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ text: String, size: CGFloat = 36, weight: Font.Weight = .medium) {
        self.text = text
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .monospacedDigit()
            .tracking(size >= 28 ? -0.5 : 0)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .modifier(ReducedMotionTransaction())
    }
}

/// Close hole: two figures, each named. Not a receipt — just what the clocks are.
public struct CloseFigures: View {
    var focus: TimeInterval
    var rest: TimeInterval
    var compact: Bool

    public init(focus: TimeInterval, rest: TimeInterval, compact: Bool = false) {
        self.focus = focus
        self.rest = rest
        self.compact = compact
    }

    public var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            figure(
                Format.clock(focus), name: "Focused", size: compact ? 26 : 36, tone: Atmosphere.canvas.ink,
                nameTone: Look.mute)
            figure(
                Format.clock(rest), name: "Break earned", size: compact ? 16 : 22,
                tone: Look.mute, nameTone: Look.faint)
        }
    }

    private func figure(_ clock: String, name: String, size: CGFloat, tone: Color, nameTone: Color) -> some View {
        VStack(spacing: compact ? 1 : 3) {
            InstrumentClock(clock, size: size)
                .foregroundStyle(tone)
            Text(name)
                .font(.system(size: compact ? 9 : 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(nameTone)
        }
    }
}

/// A short reminder of the first-session promise after the optional tutorial.
public struct FirstRunPromise: View {
    @Environment(\.atmosphere) private var atmo

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            Text("Focus counts up.")
                .foregroundStyle(atmo.ink)
            Text("Stop when you’re ready.")
                .foregroundStyle(atmo.mute)
            Text("Your break grows as you focus.")
                .foregroundStyle(Atmosphere.rest)
        }
        .font(.system(.caption).weight(.medium))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Focus counts up. Stop when you’re ready. Your break grows as you focus."
        )
    }
}

/// Quiet proof that a finished session left something useful behind.
public struct ClosePayoff: View {
    @Environment(\.atmosphere) private var atmo
    var nextStep: String
    var parkedCount: Int

    public init(nextStep: String, parkedCount: Int) {
        self.nextStep = nextStep
        self.parkedCount = parkedCount
    }

    public var body: some View {
        if !trimmedNextStep.isEmpty || safeParkedCount > 0 {
            VStack(spacing: 5) {
                if !trimmedNextStep.isEmpty {
                    Text("Next: \(trimmedNextStep)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Atmosphere.rest)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                if safeParkedCount > 0 {
                    Text(parkedConfirmation)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(atmo.faint)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var trimmedNextStep: String {
        nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var safeParkedCount: Int {
        max(0, parkedCount)
    }

    private var parkedConfirmation: String {
        safeParkedCount == 1 ? "1 thought parked" : "\(safeParkedCount) thoughts parked"
    }
}

/// One parked thought at the moment it can become a concrete next step.
/// Navigation stays inside the aperture so Reflection keeps its timed ring.
public struct ParkedThoughtReview: View {
    @Environment(\.atmosphere) private var atmo
    var text: String
    var position: Int
    var count: Int
    var onPrevious: () -> Void
    var onNext: () -> Void

    public init(
        text: String,
        position: Int,
        count: Int,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) {
        self.text = text
        self.position = position
        self.count = count
        self.onPrevious = onPrevious
        self.onNext = onNext
    }

    public var body: some View {
        if safeCount > 0 {
            VStack(spacing: 6) {
                ViewThatFits(in: .vertical) {
                    thoughtText
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        thoughtText
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(maxHeight: 96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Parked thought: \(text)")

                HStack(spacing: 10) {
                    navigationButton(
                        systemName: "chevron.left",
                        label: "Previous parked thought",
                        enabled: canMovePrevious,
                        action: onPrevious
                    )

                    Text("Parked \(safePosition) of \(safeCount)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(atmo.faint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    navigationButton(
                        systemName: "chevron.right",
                        label: "Next parked thought",
                        enabled: canMoveNext,
                        action: onNext
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
    }

    private var safeCount: Int {
        max(0, count)
    }

    private var safePosition: Int {
        guard safeCount > 0 else { return 0 }
        return min(max(1, position), safeCount)
    }

    private var canMovePrevious: Bool {
        safeCount > 0 && safePosition > 1
    }

    private var canMoveNext: Bool {
        safeCount > 0 && safePosition < safeCount
    }

    private var navigationTarget: CGFloat {
        #if os(iOS)
            44
        #else
            28
        #endif
    }

    private var thoughtText: some View {
        Text(text)
            .font(.system(.body).weight(.medium))
            .foregroundStyle(atmo.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func navigationButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? atmo.mute : atmo.faint.opacity(0.45))
                .frame(width: navigationTarget, height: navigationTarget)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityValue("Parked \(safePosition) of \(safeCount)")
    }
}

/// Gold mark with no finish line. Width grows with earned rest; the track never fills.
public struct Accrual: View {
    var seconds: TimeInterval
    var label: String

    public init(seconds: TimeInterval, label: String) {
        self.seconds = seconds
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 7) {
            if seconds >= 1 {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Atmosphere.restDeep, Atmosphere.rest],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: min(96, 8 + CGFloat(seconds / 60) * 18), height: 3)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .tracking(0.2)
                    .foregroundStyle(Atmosphere.rest)
            }
        }
        .frame(minHeight: 24)
    }
}

/// Explains the proportional rest at the moment it becomes useful.
public struct EarnedRestContext: View {
    var focus: TimeInterval
    var rest: TimeInterval

    public init(focus: TimeInterval, rest: TimeInterval) {
        self.focus = focus
        self.rest = rest
    }

    public var body: some View {
        Text("\(Format.minutes(rest)) earned from \(Format.minutes(focus)) focus")
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .tracking(0.2)
            .foregroundStyle(Atmosphere.rest)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

public struct FieldCanvas: View {
    public init() {}

    /// Every falloff is concentric on the aperture. A vertical wash would draw a
    /// straight iso-line across the width and read as a footer panel.
    public var body: some View {
        GeometryReader { geo in
            let reach = hypot(geo.size.width, geo.size.height)
            ZStack {
                Atmosphere.canvas.field
                RadialGradient(
                    colors: [
                        Color(red: 28 / 255, green: 24 / 255, blue: 16 / 255).opacity(0.42),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.40),
                    startRadius: reach * 0.03,
                    endRadius: reach * 0.80
                )
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.038),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.34, y: 0.08),
                    startRadius: 0,
                    endRadius: reach * 0.50
                )
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.26),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.44),
                    startRadius: reach * 0.30,
                    endRadius: reach * 1.0
                )
            }
        }
        .ignoresSafeArea()
    }
}

public struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
            .modifier(ReducedMotionTransaction())
    }
}

/// Start / Continue keep a stable shape and respond with a small tonal change.
public struct InkPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(InkHover(pressed: configuration.isPressed))
    }
}

private struct InkHover: ViewModifier {
    var pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .opacity(pressed ? 0.88 : 1)
            .brightness(hovering && isEnabled && !pressed ? 0.035 : 0)
            .animation(reduceMotion ? nil : Motion.press, value: pressed)
            .animation(reduceMotion ? nil : Motion.hover, value: hovering)
            .onHover { hovering = isEnabled && $0 }
            .modifier(ReducedMotionTransaction())
    }
}

/// Skip / History / Guard: well + ink on the label. Never an underline, never a grow.
public struct QuietHoverInk: ViewModifier {
    /// How far the well reaches past the label. Bare labels need the room;
    /// controls that already pad their own label pass `.zero`.
    var reach: CGSize

    @Environment(\.atmosphere) private var atmo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    public init(reach: CGSize = CGSize(width: 8, height: 4)) {
        self.reach = reach
    }

    public func body(content: Content) -> some View {
        content
            .underline(false)
            .fontWeight(.medium)
            .foregroundStyle(hovering && isEnabled ? atmo.ink : atmo.mute)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(atmo.ink.opacity(hovering && isEnabled ? 0.08 : restingWellOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                atmo.ink.opacity(hovering && isEnabled ? 0.16 : restingWellOpacity),
                                lineWidth: 0.5
                            )
                    }
                    .padding(.horizontal, -reach.width)
                    .padding(.vertical, -reach.height)
            }
            .animation(reduceMotion ? nil : Motion.hover, value: hovering)
            .onHover { hovering = isEnabled && $0 }
            .modifier(ReducedMotionTransaction())
    }

    private var restingWellOpacity: Double {
        #if os(iOS)
            0.035
        #else
            0
        #endif
    }
}

private struct ReducedMotionTransaction: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}

private enum InstrumentControlMetrics {
    static func minimumHeight(compact: Bool) -> CGFloat {
        #if os(iOS)
            44
        #else
            compact ? 28 : 36
        #endif
    }
}

public struct InkButton: View {
    @Environment(\.atmosphere) private var atmo
    @Environment(\.isEnabled) private var isEnabled
    var title: String
    var compact: Bool
    var action: () -> Void

    public init(_ title: String, compact: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.compact = compact
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(compact ? .footnote : .body).weight(.semibold))
                .frame(minWidth: compact ? 52 : 76)
                .padding(.horizontal, compact ? 10 : 18)
                .padding(.vertical, compact ? 4 : 8)
                .frame(minHeight: InstrumentControlMetrics.minimumHeight(compact: compact))
                .background(
                    RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                        .fill(atmo.ink)
                        .overlay {
                            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                                .strokeBorder(atmo.field.opacity(0.12), lineWidth: 0.5)
                        }
                )
                .foregroundStyle(atmo.field)
                .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(InkPressStyle())
    }
}

public struct QuietButton: View {
    @Environment(\.atmosphere) private var atmo
    var title: String
    var minHeight: CGFloat
    var compact: Bool
    var action: () -> Void

    public init(
        _ title: String,
        minHeight: CGFloat = 32,
        compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.minHeight = minHeight
        self.compact = compact
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(compact ? .footnote : .body).weight(.medium))
                .underline(false)
                .lineLimit(compact ? 1 : nil)
                .padding(.horizontal, compact ? 8 : 12)
                .frame(minHeight: max(minHeight, InstrumentControlMetrics.minimumHeight(compact: compact)))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .modifier(QuietHoverInk(reach: .zero))
        }
        .buttonStyle(PressStyle())
    }
}

/// Recovery only. Restart drops the frozen session. Continue resumes it.
public struct RecoveryVerbs: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var compact: Bool
    var onRestart: () -> Void
    var onContinue: () -> Void

    public init(compact: Bool = false, onRestart: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.compact = compact
        self.onRestart = onRestart
        self.onContinue = onContinue
    }

    public var body: some View {
        #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    buttons
                }
            } else {
                horizontalButtons
            }
        #else
            horizontalButtons
        #endif
    }

    private var horizontalButtons: some View {
        HStack(spacing: compact ? 8 : 10) {
            buttons
        }
    }

    @ViewBuilder
    private var buttons: some View {
        QuietButton("Restart", minHeight: compact ? 28 : PhaseGrid.verb, compact: compact, action: onRestart)
        InkButton("Continue", compact: compact, action: onContinue)
            .keyboardShortcut(.defaultAction)
    }
}

public enum PhaseGrid {
    public static let head: CGFloat = 44
    #if os(iOS)
        public static let verb: CGFloat = 44
        /// Today / History / New. Live phases keep the empty slot so the hole does not grow into Start.
        public static let chrome: CGFloat = 40
    #else
        public static let verb: CGFloat = 36
        /// Today / History / New + Guard. Live phases keep the empty slot so the hole does not grow into Start.
        public static let chrome: CGFloat = 64
    #endif
    public static let gap: CGFloat = 10
}

/// Same slots on every phase so the circle does not jump. Chrome is reserved even when empty.
public struct PhaseColumn<Head: View, Hole: View, Verb: View, Chrome: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var head: Head
    var hole: Hole
    var verb: Verb
    var chrome: Chrome

    public init(
        @ViewBuilder head: () -> Head,
        @ViewBuilder hole: () -> Hole,
        @ViewBuilder verb: () -> Verb,
        @ViewBuilder chrome: () -> Chrome
    ) {
        self.head = head()
        self.hole = hole()
        self.verb = verb()
        self.chrome = chrome()
    }

    public var body: some View {
        #if os(iOS)
            GeometryReader { geometry in
                let expanded = dynamicTypeSize.isAccessibilitySize || geometry.size.height < 480
                let availableHole =
                    geometry.size.height - PhaseGrid.head - PhaseGrid.verb
                    - max(PhaseGrid.chrome, 64) - PhaseGrid.gap * 3
                let compactHole = max(
                    96,
                    min(geometry.size.width, dynamicTypeSize.isAccessibilitySize ? 320 : availableHole)
                )
                // Keep the field in one hierarchy when the keyboard changes the
                // available height. Only slot dimensions change; focus survives.
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: PhaseGrid.gap) {
                            head
                                .fixedSize(horizontal: false, vertical: expanded)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: PhaseGrid.head,
                                    maxHeight: expanded ? nil : PhaseGrid.head
                                )
                            hole
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: expanded ? compactHole : 96,
                                    maxHeight: expanded ? compactHole : .infinity
                                )
                            verb
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: PhaseGrid.verb
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        chrome
                            .frame(maxWidth: .infinity, minHeight: PhaseGrid.chrome, alignment: .top)
                            .padding(.top, expanded ? PhaseGrid.gap : 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        #else
            fixedColumn
        #endif
    }

    private var fixedColumn: some View {
        VStack(spacing: 0) {
            VStack(spacing: PhaseGrid.gap) {
                head
                    .frame(maxWidth: .infinity, minHeight: PhaseGrid.head, maxHeight: PhaseGrid.head)
                // Not clipped: the slot edge would cut the aperture's glow into a
                // straight seam and the field below would read as a panel.
                hole
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                verb
                    .frame(maxWidth: .infinity, minHeight: PhaseGrid.verb, maxHeight: PhaseGrid.verb)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            chrome
                .frame(maxWidth: .infinity, minHeight: PhaseGrid.chrome, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Empty reserved chrome. Color.clear alone expands and crushes the hole.
public struct PhaseChromeSpace: View {
    public init() {}

    public var body: some View {
        Color.clear.frame(height: PhaseGrid.chrome)
    }
}

extension PhaseColumn where Chrome == PhaseChromeSpace {
    public init(
        @ViewBuilder head: () -> Head,
        @ViewBuilder hole: () -> Hole,
        @ViewBuilder verb: () -> Verb
    ) {
        self.init(head: head, hole: hole, verb: verb, chrome: { PhaseChromeSpace() })
    }
}

public struct PhaseCaption: View {
    var text: String
    var tone: Color

    public init(_ text: String, tone: Color = Atmosphere.canvas.ink) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(.system(.body).weight(.medium))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct HairlineField: View {
    @Environment(\.atmosphere) private var atmo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var placeholder: String
    @Binding var text: String
    var centered: Bool

    public init(_ placeholder: String, text: Binding<String>, centered: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.centered = centered
    }

    @FocusState private var focused: Bool

    public var body: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundColor(atmo.mute))
            .textFieldStyle(.plain)
            .focused($focused)
            .font(.system(.body).weight(.medium))
            .multilineTextAlignment(centered ? .center : .leading)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(atmo.ink.opacity(focused ? 0.42 : 0.13))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                    .animation(reduceMotion ? nil : Motion.hover, value: focused)
            }
            .modifier(ReducedMotionTransaction())
    }
}
