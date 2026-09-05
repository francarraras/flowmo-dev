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
    @State private var idlePulse = false

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let diameter = min(side, max(96, side * 0.92))
            ZStack {
                well
                ringView
                AssembleIn {
                    content.padding(contentPadding)
                }
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: glowColor, radius: glowRadius, x: 0, y: 8)
            .scaleEffect(idleScale)
            .animation(
                ringEqualsIdle && !reduceMotion ? Motion.breathe : nil,
                value: idlePulse
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .onAppear {
            guard !reduceMotion, ring == .idle else { return }
            idlePulse = true
        }
        .onChange(of: ringEqualsIdle) { _, isIdle in
            if reduceMotion {
                idlePulse = false
            } else {
                idlePulse = isIdle
            }
        }
    }

    private var ringEqualsIdle: Bool {
        if case .idle = ring { return true }
        return false
    }

    private var idleScale: CGFloat {
        if reduceMotion { return 1 }
        if case .idle = ring { return idlePulse ? 1.018 : 1 }
        return 1
    }

    private var glowColor: Color {
        switch ring {
        case .timed(_, true, true):
            return Atmosphere.rest.opacity(0.48)
        case .timed(_, true, false):
            return Atmosphere.rest.opacity(0.28)
        case .none:
            return Color.black.opacity(0.35)
        default:
            return Color.black.opacity(0.45)
        }
    }

    private var glowRadius: CGFloat {
        switch ring {
        case .timed(_, true, true): return 26
        case .timed(_, true, false): return 18
        case .none: return 10
        default: return 14
        }
    }

    private var well: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 24 / 255, green: 22 / 255, blue: 17 / 255),
                        Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255),
                        Color.black.opacity(0.62),
                    ],
                    center: UnitPoint(x: 0.42, y: 0.36),
                    startRadius: 2,
                    endRadius: 130
                )
            )
            .overlay { LunarCore() }
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.075),
                                Color.white.opacity(0.02),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.34, y: 0.28),
                            startRadius: 2,
                            endRadius: 88
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.03),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(Circle())
    }

    @ViewBuilder
    private var ringView: some View {
        let line: CGFloat = 5
        switch ring {
        case .none:
            EmptyView()
        case .idle:
            PuzzleRing(line: line, color: atmo.track.opacity(0.9), rest: false, race: false, progress: nil) {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .padding(line / 2)
            }
        case .timed(let progress, let rest, let race):
            PuzzleRing(
                line: line,
                color: atmo.track,
                rest: rest,
                race: race,
                progress: progress
            ) {
                EmptyView()
            }
        }
    }
}

/// Surface turns. Sunlight does not. The circle stays put.
private struct LunarCore: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn = 0.0

    /// Plains, not holes: floors at warm charcoal so the rim side of the turn
    /// still reads as ground instead of sinking into the vignette.
    private static let mare = Color(red: 12 / 255, green: 11 / 255, blue: 9 / 255)

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Ellipse()
                    .fill(Self.mare.opacity(0.72))
                    .frame(width: d * 0.46, height: d * 0.36)
                    .offset(x: -d * 0.14, y: d * 0.04)
                    .blur(radius: d * 0.038)
                Ellipse()
                    .fill(Self.mare.opacity(0.60))
                    .frame(width: d * 0.30, height: d * 0.24)
                    .offset(x: d * 0.18, y: -d * 0.16)
                    .blur(radius: d * 0.032)
                Ellipse()
                    .fill(Self.mare.opacity(0.52))
                    .frame(width: d * 0.20, height: d * 0.17)
                    .offset(x: d * 0.02, y: d * 0.22)
                    .blur(radius: d * 0.028)
                Ellipse()
                    .fill(Atmosphere.canvas.ink.opacity(0.05))
                    .frame(width: d * 0.22, height: d * 0.18)
                    .offset(x: d * 0.16, y: d * 0.10)
                    .blur(radius: d * 0.045)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .rotationEffect(.degrees(reduceMotion ? 0 : turn))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.moon) {
                turn = 360
            }
        }
    }
}

/// Four arcs start apart and click into one track. Inverse of a blast.
private struct PuzzleRing<Highlight: View>: View {
    var line: CGFloat
    var color: Color
    var rest: Bool
    var race: Bool
    var progress: Double?
    var highlight: Highlight

    @Environment(\.atmosphere) private var atmo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var assembled = false

    init(
        line: CGFloat,
        color: Color,
        rest: Bool,
        race: Bool,
        progress: Double?,
        @ViewBuilder highlight: () -> Highlight
    ) {
        self.line = line
        self.color = color
        self.rest = rest
        self.race = race
        self.progress = progress
        self.highlight = highlight()
    }

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                piece(i)
            }
            if assembled, let progress {
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(
                        rest
                            ? AngularGradient(
                                colors: [Atmosphere.restDeep, Atmosphere.rest, Atmosphere.restDeep],
                                center: .center
                            )
                            : AngularGradient(
                                colors: [atmo.mute, atmo.ink.opacity(0.85), atmo.mute],
                                center: .center
                            ),
                        style: StrokeStyle(lineWidth: line, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(
                        color: rest ? Atmosphere.rest.opacity(race ? 0.85 : 0.55) : Color.clear,
                        radius: race ? 14 : 8
                    )
                    .animation(reduceMotion ? nil : Motion.tick, value: progress)
                    .animation(reduceMotion ? nil : Motion.race, value: race)
            }
            if assembled {
                highlight
            }
        }
        .onAppear { settle() }
    }

    private func piece(_ i: Int) -> some View {
        let bearing = Double(i) * 90 + 45
        let throwOut: CGFloat = assembled ? 0 : 11
        let twist: Double = assembled ? 0 : (i % 2 == 0 ? -16 : 16)
        let span: CGFloat = assembled ? 0.25 : 0.13
        let start = CGFloat(i) * 0.25 + (assembled ? 0 : 0.06)
        return Circle()
            .trim(from: start, to: start + span)
            .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: assembled ? .butt : .round))
            .rotationEffect(.degrees(-90 + twist))
            .offset(
                x: throwOut * sin(bearing * .pi / 180),
                y: throwOut * -cos(bearing * .pi / 180)
            )
            .opacity(assembled ? 1 : 0.7)
    }

    private func settle() {
        if reduceMotion {
            assembled = true
            return
        }
        assembled = false
        withAnimation(Motion.assemble) {
            assembled = true
        }
    }
}

/// Hole contents implode into place. They do not fly off.
private struct AssembleIn<Content: View>: View {
    var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var assembled = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(assembled ? 1 : 1.16)
            .opacity(assembled ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    assembled = true
                } else {
                    withAnimation(Motion.assemble) {
                        assembled = true
                    }
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

    public init(_ text: String, size: CGFloat = 36, weight: Font.Weight = .medium) {
        self.text = text
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .tracking(size >= 28 ? -1.4 : 0.2)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText())
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
                .font(.system(size: compact ? 9 : 11, weight: .medium, design: .rounded))
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
        .font(.system(.caption, design: .rounded).weight(.medium))
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
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Atmosphere.rest)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                if safeParkedCount > 0 {
                    Text(parkedConfirmation)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
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
                        .font(.system(size: 10, weight: .medium, design: .rounded))
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
            .font(.system(.body, design: .rounded).weight(.medium))
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
                    .shadow(color: Atmosphere.rest.opacity(0.7), radius: 6, y: 0)
                    .animation(Motion.rest, value: seconds)
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
            .font(.system(size: 12, weight: .semibold, design: .rounded))
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
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Start / Continue: the chip lights, it does not grow.
public struct InkPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(InkHover(pressed: configuration.isPressed))
    }
}

private struct InkHover: ViewModifier {
    var pressed: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(pressed ? 0.88 : 1)
            .brightness(hovering && !pressed ? 0.08 : 0)
            .shadow(
                color: Atmosphere.canvas.ink.opacity(hovering && !pressed ? 0.42 : 0.28),
                radius: hovering && !pressed ? 16 : 10,
                y: hovering && !pressed ? 6 : 4
            )
            .animation(Motion.press, value: pressed)
            .animation(Motion.hover, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Skip / History / Guard: well + ink on the label. Never an underline, never a grow.
public struct QuietHoverInk: ViewModifier {
    /// How far the well reaches past the label. Bare labels need the room;
    /// controls that already pad their own label pass `.zero`.
    var reach: CGSize

    @Environment(\.atmosphere) private var atmo
    @State private var hovering = false

    public init(reach: CGSize = CGSize(width: 8, height: 4)) {
        self.reach = reach
    }

    public func body(content: Content) -> some View {
        content
            .underline(false)
            .fontWeight(.medium)
            .foregroundStyle(hovering ? atmo.ink : atmo.mute)
            .background {
                Capsule()
                    .fill(atmo.ink.opacity(hovering ? 0.16 : 0))
                    .overlay {
                        Capsule()
                            .strokeBorder(atmo.ink.opacity(hovering ? 0.28 : 0), lineWidth: 1)
                    }
                    .padding(.horizontal, -reach.width)
                    .padding(.vertical, -reach.height)
            }
            .animation(Motion.hover, value: hovering)
            .onHover { hovering = $0 }
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
                .font(.system(compact ? .footnote : .body, design: .rounded).weight(.semibold))
                .frame(minWidth: compact ? 52 : 76)
                .padding(.horizontal, compact ? 10 : 18)
                .padding(.vertical, compact ? 4 : 8)
                .background(
                    Capsule()
                        .fill(atmo.ink)
                        .shadow(color: atmo.ink.opacity(0.28), radius: compact ? 6 : 10, y: compact ? 2 : 4)
                )
                .foregroundStyle(atmo.field)
                .contentShape(Capsule())
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
                .font(.system(compact ? .footnote : .body, design: .rounded).weight(.medium))
                .underline(false)
                .lineLimit(compact ? 1 : nil)
                .padding(.horizontal, compact ? 8 : 12)
                .frame(minHeight: minHeight)
                .contentShape(Capsule())
                .modifier(QuietHoverInk(reach: .zero))
        }
        .buttonStyle(PressStyle())
    }
}

/// Recovery only. Restart drops the frozen session. Continue resumes it.
public struct RecoveryVerbs: View {
    var compact: Bool
    var onRestart: () -> Void
    var onContinue: () -> Void

    public init(compact: Bool = false, onRestart: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.compact = compact
        self.onRestart = onRestart
        self.onContinue = onContinue
    }

    public var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            QuietButton("Restart", minHeight: compact ? 26 : PhaseGrid.verb, action: onRestart)
            InkButton("Continue", compact: compact, action: onContinue)
                .keyboardShortcut(.defaultAction)
        }
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
                                .fixedSize(horizontal: false, vertical: expanded)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: PhaseGrid.verb,
                                    maxHeight: expanded ? nil : PhaseGrid.verb
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
            .font(.system(.body, design: .rounded).weight(.medium))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct HairlineField: View {
    @Environment(\.atmosphere) private var atmo
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
            .font(.system(.body, design: .rounded).weight(.medium))
            .multilineTextAlignment(centered ? .center : .leading)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .leading)
            .overlay(alignment: .bottom) {
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
    }
}
