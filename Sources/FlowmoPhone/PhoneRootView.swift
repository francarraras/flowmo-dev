import FlowmoCore
import FlowmoLook
import FlowmoSync
import SwiftUI
import UniformTypeIdentifiers

enum PhoneFocusPresentation {
    static func usesDistantHorizon(
        phase: SessionPhase?,
        isPaused: Bool,
        storeNeedsRecovery: Bool,
        hasSyncConflict: Bool
    ) -> Bool {
        phase == .focus
            && !isPaused
            && !storeNeedsRecovery
            && !hasSyncConflict
    }
}

public struct PhoneRootView: View {
    @ObservedObject var controller: PhoneSessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(controller: PhoneSessionController) {
        self.controller = controller
    }

    public var body: some View {
        let status = controller.status
        let atmo = Atmosphere.of(status)
        let introduction = controller.introduction.isPresented && controller.canShowIntroduction
        let distantHorizon = PhoneFocusPresentation.usesDistantHorizon(
            phase: status.phase,
            isPaused: status.isPaused,
            storeNeedsRecovery: controller.storeNeedsRecovery,
            hasSyncConflict: controller.syncStatus.conflict != nil
        )
        Group {
            if controller.storeNeedsRecovery {
                StoreRecoveryPane(controller: controller)
            } else if let conflict = controller.syncStatus.conflict {
                SyncConflictPane(controller: controller, conflict: conflict)
            } else if introduction {
                IntroductionView(
                    state: controller.introduction,
                    onRequestNotifications: controller.requestNotifications
                )
            } else if status.isIdle {
                IdlePane(controller: controller, status: status)
            } else {
                phasePane(status, usesDistantHorizon: distantHorizon)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, distantHorizon ? 0 : 20)
        .padding(.bottom, distantHorizon ? 0 : 20)
        .padding(.top, distantHorizon ? 0 : 12)
        .foregroundStyle(atmo.ink)
        .background(FieldCanvas())
        .environment(\.atmosphere, atmo)
        .animation(reduceMotion ? nil : Motion.phase, value: status.isPaused)
        .animation(reduceMotion ? nil : Motion.phase, value: distantHorizon)
        .preferredColorScheme(.dark)
        .onAppear { controller.presentIntroductionIfNeeded() }
        .onChange(of: controller.canShowIntroduction) { _, _ in
            controller.presentIntroductionIfNeeded()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !distantHorizon, !introduction {
                HStack {
                    Spacer()
                    PhoneMuteButton(controller: controller)
                }
                .opacity(controller.storeNeedsRecovery ? 0 : atmo.chrome)
                .allowsHitTesting(!controller.storeNeedsRecovery)
            }
        }
        .alert(item: $controller.activeIssue) { issue in
            Alert(
                title: Text(issue.title),
                message: Text("\(issue.message)\n\nIssue code: \(issue.code.rawValue)"),
                dismissButton: .default(Text("OK"))
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                if let notice = controller.userNotice {
                    Text(notice)
                        .contentShape(Rectangle())
                        .onTapGesture { controller.clearNotice() }
                }
                if !controller.isLocalOnly, let notice = worldSyncNotice(controller.syncStatus) {
                    Text(notice)
                }
            }
            .font(.system(.caption, design: .rounded).weight(.medium))
            .foregroundStyle(atmo.mute)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func phasePane(_ status: SessionStatus, usesDistantHorizon: Bool) -> some View {
        switch status.phase {
        case .prime:
            PrimePane(controller: controller, status: status)
        case .focus:
            FocusPane(
                controller: controller,
                status: status,
                usesDistantHorizon: usesDistantHorizon
            )
        case .onBreak:
            BreakPane(controller: controller, status: status)
        case .recall:
            RecallPane(controller: controller, status: status)
        case .closeBeat:
            CloseBeatPane(controller: controller, status: status)
        case nil:
            IdlePane(controller: controller, status: status)
        }
    }
}

private struct PhoneMuteButton: View {
    @ObservedObject var controller: PhoneSessionController

    var body: some View {
        let on = controller.world.config.cuesEnabled
        Button {
            controller.setCuesEnabled(!on)
        } label: {
            ChromeGlyph(on ? "speaker.wave.2" : "speaker.slash", lit: on)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(on ? "Mute cues" : "Unmute cues")
    }
}

@MainActor
private func worldSyncNotice(_ status: WorldSyncStatus) -> String? {
    guard status.phase == .unavailable else { return nil }
    switch status.issueCode {
    case "sync_deletion_account_unavailable":
        return "Sign back into the previous iCloud account to finish deletion."
    case "sync_deletion_pending":
        return "iCloud deletion is pending."
    case "sync_entitlement_unavailable", "sync_account_unavailable":
        return nil
    default:
        return "iCloud sync is unavailable. Flowmo is working locally."
    }
}

private struct SyncConflictPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    let conflict: WorldSyncConflict

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Choose what to keep")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(atmo.mute)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                InkButton("Keep this iPhone") {
                    controller.resolveSyncConflict(conflict, choosing: .local)
                }
                InkButton("Use iCloud version") {
                    controller.resolveSyncConflict(conflict, choosing: .remote)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        switch conflict.kind {
        case .account:
            "The iCloud account changed. Flowmo will not move private session data between accounts without your choice."
        case .liveSession:
            "Two sessions were started offline. This iPhone has \(summary(conflict.local)); iCloud has \(summary(conflict.remote))."
        case .initialImport:
            "This iPhone and iCloud both contain Flowmo data. Nothing will be overwritten until you choose."
        case .resetGeneration:
            "One copy was reset while the other changed. Choose the complete copy you want to keep."
        case .profile, .completedSession:
            "This iPhone and iCloud changed the same Flowmo data. Choose the copy you want to keep."
        }
    }

    private func summary(_ snapshot: WorldSyncSnapshot) -> String {
        guard let live = snapshot.head.live else { return "no active session" }
        let intention = live.intention.trimmingCharacters(in: .whitespacesAndNewlines)
        return intention.isEmpty ? "an active session" : "“\(intention)”"
    }
}

public struct PhoneStoreUnavailableView: View {
    private let retry: () -> Void
    private let isLocalOnly: Bool

    public init(isLocalOnly: Bool = false, retry: @escaping () -> Void) {
        self.isLocalOnly = isLocalOnly
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Flowmo unavailable")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(
                isLocalOnly
                    ? "Flowmo can’t access its local data right now."
                    : "Flowmo can’t access its shared local data right now."
            )
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Look.mute)
            .multilineTextAlignment(.center)
            Text(FlowmoIssueCode.storeUnavailable.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Look.faint)
            InkButton("Retry", action: retry)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Look.ink)
        .background(FieldCanvas())
        .preferredColorScheme(.dark)
    }
}

private struct IdlePane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus
    @State private var showingHistory = false
    @State private var showingData = false

    var body: some View {
        Group {
            if showingData {
                DataControlsPane(controller: controller) {
                    showingData = false
                }
            } else if showingHistory {
                HistoryPane(
                    controller: controller,
                    sessions: HistoryOrder.newestFirst(controller.world.history)
                ) {
                    showingHistory = false
                }
            } else {
                PhaseColumn {
                    HairlineField("Intention", text: $controller.intentionDraft)
                } hole: {
                    Aperture(ring: .idle) {
                        if isFirstRun {
                            FirstRunPromise()
                        }
                    }
                } verb: {
                    InkButton(startButtonTitle) {
                        performIdleAction()
                    }
                    .disabled(!canStart)
                } chrome: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            today
                            footerActions
                        }
                        VStack(spacing: 4) {
                            today
                            footerActions
                        }
                    }
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var today: some View {
        Text("Today \(Format.clock(status.todayFocusSeconds))")
            .foregroundStyle(atmo.faint)
            .monospacedDigit()
            .fixedSize()
    }

    private var footerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                footerButtons
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 4) {
                footerButtons
            }
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        footerButton("History") { showingHistory = true }
        footerButton("Data") { showingData = true }
        if !controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            footerButton("New") { controller.clearIntention() }
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fixedSize()
                .modifier(QuietHoverInk())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private var typedIntention: String {
        controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedIntention: String {
        status.lastIntention.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nextStep: String? {
        NextStepSuggestion.latest(in: controller.world.history)
    }

    private var isFirstRun: Bool {
        controller.world.history.isEmpty
            && controller.world.profile.sessionCount == 0
            && savedIntention.isEmpty
    }

    private var canStart: Bool {
        !typedIntention.isEmpty || nextStep != nil || !savedIntention.isEmpty
    }

    private var startButtonTitle: String {
        guard typedIntention.isEmpty else { return "Start" }
        if nextStep != nil { return "Use next" }
        return savedIntention.isEmpty ? "Start" : "Use last"
    }

    private func performIdleAction() {
        if typedIntention.isEmpty, nextStep != nil {
            controller.useNextStep()
        } else if typedIntention.isEmpty && !savedIntention.isEmpty {
            controller.useLastIntention()
        } else {
            controller.start()
        }
    }
}

private struct StoreRecoveryPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    @State private var exportingDiagnostics = false
    @State private var diagnosticDocument: FlowmoJSONDocument?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Data needs attention")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(
                controller.canPreserveAndReset
                    ? "Flowmo couldn’t read its local data. Retry, or preserve the original and reset."
                    : "Flowmo couldn’t safely recover its local session. Retry when local data is available."
            )
            .font(.system(.body, design: .rounded))
            .foregroundStyle(atmo.mute)
            .multilineTextAlignment(.center)
            Text(
                controller.canPreserveAndReset
                    ? FlowmoIssueCode.storeUnreadable.rawValue
                    : FlowmoIssueCode.persistenceFailed.rawValue
            )
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(atmo.faint)
            VStack(spacing: 10) {
                InkButton("Retry") { controller.retryStore() }
                if controller.canPreserveAndReset {
                    QuietButton("Preserve & Reset", minHeight: 44) {
                        controller.preserveAndResetStore()
                    }
                }
                QuietButton("Export Redacted Diagnostics", minHeight: 44) {
                    guard let data = controller.prepareDiagnosticExport() else { return }
                    diagnosticDocument = FlowmoJSONDocument(data: data)
                    exportingDiagnostics = true
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileExporter(
            isPresented: $exportingDiagnostics,
            document: diagnosticDocument,
            contentType: .json,
            defaultFilename: "flowmo-diagnostics"
        ) { result in
            switch result {
            case .success:
                controller.exportFinished(kind: "diagnostics", succeeded: true)
            case .failure(let error):
                if !FlowmoExportResult.isUserCancellation(error) {
                    controller.exportFinished(kind: "diagnostics", succeeded: false)
                }
            }
            diagnosticDocument = nil
        }
    }
}

private struct DataControlsPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    var dismiss: () -> Void
    @State private var showingDeleteConfirmation = false
    @State private var exporting = false
    @State private var exportKind = "data"
    @State private var exportDocument: FlowmoJSONDocument?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    QuietButton("Back", minHeight: 44, action: dismiss)
                    Spacer()
                    Text("Data")
                        .font(.system(.headline, design: .rounded))
                }
                Spacer()
                Text(
                    controller.isLocalOnly
                        ? "Sessions stay in this app on this iPhone. Exports go only where you choose to save them."
                        : "Exports stay on this device unless you choose where to save them."
                )
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(atmo.mute)
                .multilineTextAlignment(.center)
                InkButton("Export Flowmo Data") {
                    beginExport(kind: "data")
                }
                QuietButton("Export Redacted Diagnostics", minHeight: 44) {
                    beginExport(kind: "diagnostics")
                }
                QuietButton("Delete All Data", minHeight: 44) {
                    showingDeleteConfirmation = true
                }
                .foregroundStyle(Color.red.opacity(0.85))
                Divider()
                QuietButton("How it works", minHeight: 44) {
                    controller.showIntroduction()
                }
                QuietButton("Enable notifications", minHeight: 44) {
                    controller.requestNotifications()
                }
                Text("If alerts were previously declined, enable them in system settings.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(atmo.mute)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete all Flowmo data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) {
                controller.deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                controller.isLocalOnly
                    ? "This permanently deletes Flowmo data in this app on this iPhone. This cannot be undone."
                    : "This permanently deletes Flowmo data on this iPhone and removes its synced iCloud copy when one exists. Other synced devices receive that deletion. If you’re offline, iCloud deletion stays pending. This cannot be undone."
            )
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportKind == "diagnostics" ? "flowmo-diagnostics" : "flowmo-data"
        ) { result in
            switch result {
            case .success:
                controller.exportFinished(kind: exportKind, succeeded: true)
            case .failure(let error):
                if !FlowmoExportResult.isUserCancellation(error) {
                    controller.exportFinished(kind: exportKind, succeeded: false)
                }
            }
            exportDocument = nil
        }
    }

    private func beginExport(kind: String) {
        let data =
            kind == "diagnostics"
            ? controller.prepareDiagnosticExport()
            : controller.prepareFullDataExport()
        guard let data else { return }
        exportKind = kind
        exportDocument = FlowmoJSONDocument(data: data)
        exporting = true
    }
}

private struct HistoryPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    var sessions: [CompletedSession]
    var dismiss: () -> Void
    @State private var expandedID: UUID?
    @State private var pendingResumption: CompletedSession?
    @State private var showingReplacementConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                QuietButton("Back", minHeight: 44, action: dismiss)
                Spacer()
                Text("History")
                    .font(.system(.headline, design: .rounded))
            }
            if sessions.isEmpty {
                Text("No completed sessions yet.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(atmo.mute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sessions, id: \.id) { session in
                            HistorySessionCard(
                                session: session,
                                expanded: expandedID == session.id,
                                resumptionTitle: resumptionTitle(for: session),
                                onResume: { attemptResumption(session) },
                                onToggle: {
                                    withAnimation(Motion.phase) {
                                        expandedID = expandedID == session.id ? nil : session.id
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Replace current intention?",
            isPresented: $showingReplacementConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace intention") {
                guard let pendingResumption else { return }
                finishResumption(pendingResumption, replacingCurrentDraft: true)
            }
            Button("Cancel", role: .cancel) {
                pendingResumption = nil
            }
        } message: {
            Text("This replaces the intention currently typed in Idle.")
        }
    }

    private func resumptionTitle(for session: CompletedSession) -> String? {
        guard SessionResumptionSuggestion.forSession(session) != nil else { return nil }
        let nextStep = session.recallText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return nextStep.isEmpty ? "Use intention" : "Use next step"
    }

    private func attemptResumption(_ session: CompletedSession) {
        let hasCurrentDraft = !controller.intentionDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        guard hasCurrentDraft else {
            finishResumption(session, replacingCurrentDraft: false)
            return
        }
        pendingResumption = session
        showingReplacementConfirmation = true
    }

    private func finishResumption(_ session: CompletedSession, replacingCurrentDraft: Bool) {
        if controller.useSessionResumption(
            session,
            replacingCurrentDraft: replacingCurrentDraft
        ) {
            pendingResumption = nil
            dismiss()
        }
    }
}

private struct PrimePane: View {
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseLead(status.intention, cue: "Prepare")
        } hole: {
            Aperture(ring: .timed(progress: ringProgress(status))) {
                InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 40)
            }
        } verb: {
            if status.isPaused {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            } else {
                QuietButton("Focus now", minHeight: 44) { controller.skip() }
            }
        }
    }
}

private struct FocusPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus
    var usesDistantHorizon: Bool

    var body: some View {
        if usesDistantHorizon {
            PhoneDistantHorizonFocusPane(controller: controller, status: status)
        } else {
            PhaseColumn {
                PhaseLead(status.intention, cue: "Focus", tone: atmo.mute)
            } hole: {
                Aperture(ring: .none) {
                    VStack(spacing: 10) {
                        InstrumentClock(Format.clock(status.elapsed), size: 56)
                        Accrual(
                            seconds: status.earnedBreakSeconds,
                            label: Format.earned(status.earnedBreakSeconds)
                        )
                    }
                }
            } verb: {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            }
        }
    }
}

private struct PhoneDistantHorizonFocusPane: View {
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleScale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var interfaceScale: CGFloat = 1
    @FocusState private var captureFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let landscape = size.width > size.height
            let baseHorizontalInset = min(64, max(24, size.width * 0.064))
            let leadingInset = max(baseHorizontalInset, proxy.safeAreaInsets.leading + 16)
            let trailingInset = max(baseHorizontalInset, proxy.safeAreaInsets.trailing + 16)
            let topInset = max(
                proxy.safeAreaInsets.top + 18,
                landscape ? size.height * 0.08 : size.height * 0.105
            )
            let bottomInset = max(proxy.safeAreaInsets.bottom + 14, landscape ? 16 : 24)

            ZStack {
                DistantHorizonBackdrop()

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        sceneHeader(width: size.width, landscape: landscape)

                        Spacer(minLength: landscape ? 18 : 44)

                        sceneActions
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(0, size.height - topInset - bottomInset),
                        alignment: .topLeading
                    )
                    .padding(.leading, leadingInset)
                    .padding(.trailing, trailingInset)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .frame(width: size.width)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(width: size.width, height: size.height)
        }
        .background(Atmosphere.canvas.field)
    }

    @ViewBuilder
    private func sceneHeader(width: CGFloat, landscape: Bool) -> some View {
        let kickerSize = min(18, max(13, width * 0.033) * interfaceScale)
        let baseTitleSize =
            landscape
            ? min(50, max(34, width * 0.064))
            : min(52, max(38, width * 0.102))
        let titleSize = min(dynamicTypeSize.isAccessibilitySize ? 68 : 58, baseTitleSize * titleScale)
        let clockSize = min(42, max(27, width * (landscape ? 0.052 : 0.080)) * interfaceScale)
        let spacing = landscape ? 9.0 : 14.0

        if controller.showCapture {
            VStack(alignment: .leading, spacing: spacing) {
                sceneKicker("Park a thought", size: kickerSize)

                HairlineField("Thought", text: $controller.captureDraft)
                    .focused($captureFocused)
                    .frame(maxWidth: min(620, width * 0.82), minHeight: 48, maxHeight: 68)
                    .onSubmit { controller.submitCapture() }
                    .onAppear { captureFocused = true }

                InstrumentClock(Format.clock(status.elapsed), size: clockSize)
                    .foregroundStyle(Atmosphere.rest)
                    .milestoneGrow(elapsed: status.elapsed, paused: false)

                Accrual(
                    seconds: status.earnedBreakSeconds,
                    label: Format.earned(status.earnedBreakSeconds)
                )
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                sceneKicker("Focus", size: kickerSize)

                VStack(alignment: .leading, spacing: spacing) {
                    Text(status.intention)
                        .font(.system(size: titleSize, weight: .regular, design: .rounded))
                        .foregroundStyle(Atmosphere.canvas.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    InstrumentClock(Format.clock(status.elapsed), size: clockSize)
                        .foregroundStyle(Atmosphere.rest)
                        .milestoneGrow(elapsed: status.elapsed, paused: false)

                    Accrual(
                        seconds: status.earnedBreakSeconds,
                        label: Format.earned(status.earnedBreakSeconds)
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(status.intention). Focused \(Format.clock(status.elapsed)). \(Format.earned(status.earnedBreakSeconds))."
                )
            }
        }
    }

    private func sceneKicker(_ title: String, size: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: size, weight: .medium, design: .rounded))
                .tracking(0.3)
                .foregroundStyle(Atmosphere.canvas.mute)

            Spacer(minLength: 12)

            PhoneMuteButton(controller: controller)
        }
    }

    @ViewBuilder
    private var sceneActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                if controller.showCapture {
                    PhoneHorizonAction("Discard", tone: Atmosphere.canvas.mute) {
                        controller.discardCapture()
                    }
                    PhoneHorizonAction("Park", tone: Atmosphere.canvas.ink) {
                        controller.submitCapture()
                    }
                    .disabled(
                        controller.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                } else {
                    PhoneHorizonAction(parkButtonTitle, tone: Atmosphere.canvas.ink) {
                        controller.showCapture = true
                    }
                    PhoneHorizonAction("End focus", tone: Atmosphere.rest) {
                        controller.stopFocus()
                    }
                    .accessibilityHint("Stops Focus and starts your earned break.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                if controller.showCapture {
                    PhoneHorizonAction("Discard", tone: Atmosphere.canvas.mute) {
                        controller.discardCapture()
                    }
                    Spacer(minLength: 16)
                    PhoneHorizonAction("Park", tone: Atmosphere.canvas.ink) {
                        controller.submitCapture()
                    }
                    .disabled(
                        controller.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                } else {
                    PhoneHorizonAction(parkButtonTitle, tone: Atmosphere.canvas.ink) {
                        controller.showCapture = true
                    }
                    Spacer(minLength: 16)
                    PhoneHorizonAction("End focus", tone: Atmosphere.rest) {
                        controller.stopFocus()
                    }
                    .accessibilityHint("Stops Focus and starts your earned break.")
                }
            }
        }
    }

    private var parkButtonTitle: String {
        let count = status.captures.count
        return count == 0 ? "Park thought" : "Park another · \(count)"
    }
}

private struct PhoneHorizonAction: View {
    let title: String
    let tone: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, tone: Color, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(tone)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressStyle())
    }
}

private struct BreakPane: View {
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseLead("Break", cue: "Take what you need.", tone: Look.mute)
        } hole: {
            Aperture(
                ring: .timed(
                    progress: ringProgress(status),
                    rest: true,
                    race: !status.isPaused && (status.remaining ?? 0) <= 10
                )
            ) {
                VStack(spacing: 9) {
                    InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 40)
                        .breakRace(
                            remaining: status.remaining ?? 0,
                            elapsed: status.elapsed,
                            paused: status.isPaused
                        )
                    EarnedRestContext(
                        focus: status.focusSeconds,
                        rest: status.breakSeconds ?? 0
                    )
                }
            }
        } verb: {
            if status.isPaused {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            } else {
                QuietButton("Reflect", minHeight: 44) { controller.skip() }
            }
        }
    }
}

private struct RecallPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus
    @State private var parkedIndex = 0

    var body: some View {
        PhaseColumn {
            if status.isPaused {
                PhaseCaption(status.recallText.isEmpty ? "Reflection" : status.recallText, tone: atmo.mute)
            } else if controller.showParkedReview {
                PhaseLead("Parked thoughts", cue: "Choose what comes next", tone: atmo.mute)
            } else {
                HairlineField(FlowmoCopy.reflectionPrompt, text: $controller.recallDraft, centered: true)
                    .onChange(of: controller.recallDraft) { _, _ in
                        controller.persistRecall()
                    }
                    .onSubmit { controller.skip() }
            }
        } hole: {
            Aperture(ring: .timed(progress: ringProgress(status))) {
                if controller.showParkedReview, let capture = selectedParkedThought {
                    ParkedThoughtReview(
                        text: capture.text,
                        position: parkedIndex + 1,
                        count: parkedThoughts.count,
                        onPrevious: showPreviousParkedThought,
                        onNext: showNextParkedThought
                    )
                } else {
                    InstrumentClock(Format.remainingClock(status.remaining ?? 0), size: 40)
                }
            }
        } verb: {
            if status.isPaused {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            } else if controller.showParkedReview {
                HStack(spacing: 12) {
                    QuietButton("Back", minHeight: 44) {
                        controller.endParkedReview()
                    }
                    InkButton("Use as next") {
                        useSelectedParkedThought()
                    }
                    .disabled(selectedParkedThought == nil)
                }
            } else if canReviewParkedThoughts {
                HStack(spacing: 12) {
                    QuietButton(reviewParkedTitle, minHeight: 44) {
                        parkedIndex = 0
                        controller.beginParkedReview()
                    }
                    QuietButton("Skip", minHeight: 44) { controller.skip() }
                }
            } else {
                QuietButton(reflectionActionTitle, minHeight: 44) { controller.skip() }
            }
        }
        .onChange(of: status.phase) { _, phase in
            if phase != .recall {
                controller.endParkedReview()
            }
        }
        .onChange(of: status.isPaused) { _, paused in
            if paused {
                controller.endParkedReview()
            }
        }
        .onChange(of: controller.recallDraft) { _, draft in
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                controller.endParkedReview()
            }
        }
        .onChange(of: parkedThoughts.count) { _, count in
            if count == 0 {
                controller.endParkedReview()
                parkedIndex = 0
            } else {
                parkedIndex = min(parkedIndex, count - 1)
            }
        }
    }

    private var parkedThoughts: [CaptureItem] {
        Array(status.captures.reversed())
    }

    private var selectedParkedThought: CaptureItem? {
        guard parkedThoughts.indices.contains(parkedIndex) else { return nil }
        return parkedThoughts[parkedIndex]
    }

    private var canReviewParkedThoughts: Bool {
        !parkedThoughts.isEmpty
            && controller.recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && status.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var reviewParkedTitle: String {
        parkedThoughts.count == 1 ? "Review parked thought" : "Review \(parkedThoughts.count) parked"
    }

    private func showPreviousParkedThought() {
        parkedIndex = max(0, parkedIndex - 1)
    }

    private func showNextParkedThought() {
        parkedIndex = min(parkedThoughts.count - 1, parkedIndex + 1)
    }

    private func useSelectedParkedThought() {
        guard let capture = selectedParkedThought else { return }
        _ = controller.useParkedThoughtAsNext(capture)
    }

    private var reflectionActionTitle: String {
        controller.recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Skip"
            : "Done"
    }
}

private struct CloseBeatPane: View {
    @ObservedObject var controller: PhoneSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseCaption(status.intention.isEmpty ? "Close" : status.intention, tone: Look.mute)
        } hole: {
            Aperture(ring: .none) {
                VStack(spacing: 12) {
                    CloseFigures(focus: status.focusSeconds, rest: status.breakSeconds ?? 0)
                    ClosePayoff(nextStep: status.recallText, parkedCount: status.captures.count)
                }
            }
        } verb: {
            if status.isPaused {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            } else {
                QuietButton("Done", minHeight: 44) {
                    controller.dismissCloseBeat()
                }
                .accessibilityHint(closeActionHint)
            }
        }
    }

    private var closeActionHint: String {
        status.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Finishes this session."
            : "Finishes this session and carries the next step into Idle for editing. Focus does not start."
    }
}

private func ringProgress(_ status: SessionStatus) -> Double {
    guard let duration = status.phaseDuration, duration > 0 else { return 0 }
    return min(1, max(0, status.elapsed / duration))
}
