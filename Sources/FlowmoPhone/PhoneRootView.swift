import FlowmoCore
import FlowmoLook
import FlowmoSync
import SwiftUI
import UniformTypeIdentifiers

public struct PhoneRootView: View {
    @ObservedObject var controller: PhoneSessionController

    public init(controller: PhoneSessionController) {
        self.controller = controller
    }

    public var body: some View {
        let status = controller.status
        let atmo = Atmosphere.of(status)
        Group {
            if controller.storeNeedsRecovery {
                StoreRecoveryPane(controller: controller)
            } else if let conflict = controller.syncStatus.conflict {
                SyncConflictPane(controller: controller, conflict: conflict)
            } else if status.isIdle {
                IdlePane(controller: controller, status: status)
            } else {
                phasePane(status)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 12)
        .foregroundStyle(atmo.ink)
        .background(FieldCanvas())
        .environment(\.atmosphere, atmo)
        .animation(Motion.phase, value: status.isPaused)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                muteButton(atmo)
            }
            .opacity(controller.storeNeedsRecovery ? 0 : atmo.chrome)
            .allowsHitTesting(!controller.storeNeedsRecovery)
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
                if let notice = worldSyncNotice(controller.syncStatus) {
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

    private func muteButton(_ atmo: Atmosphere) -> some View {
        let on = controller.world.config.cuesEnabled
        return Button {
            controller.setCuesEnabled(!on)
        } label: {
            ChromeGlyph(on ? "speaker.wave.2" : "speaker.slash", lit: on)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(on ? "Mute cues" : "Unmute cues")
    }

    @ViewBuilder
    private func phasePane(_ status: SessionStatus) -> some View {
        switch status.phase {
        case .prime:
            PrimePane(controller: controller, status: status)
        case .focus:
            FocusPane(controller: controller, status: status)
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
                    controller.resolveSyncConflict(choosing: .local)
                }
                InkButton("Use iCloud version") {
                    controller.resolveSyncConflict(choosing: .remote)
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

    public init(retry: @escaping () -> Void) {
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Flowmo unavailable")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text("Flowmo can’t access its shared local data right now.")
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
                    HStack(spacing: 18) {
                        Text("Today \(Format.clock(status.todayFocusSeconds))")
                            .foregroundStyle(atmo.faint)
                            .monospacedDigit()
                        Button {
                            showingHistory = true
                        } label: {
                            Text("History")
                                .underline(false)
                                .modifier(QuietHoverInk())
                        }
                        .buttonStyle(PressStyle())
                        Button {
                            showingData = true
                        } label: {
                            Text("Data")
                                .underline(false)
                                .modifier(QuietHoverInk())
                        }
                        .buttonStyle(PressStyle())
                        if !controller.intentionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                controller.clearIntention()
                            } label: {
                                Text("New")
                                    .underline(false)
                                    .modifier(QuietHoverInk())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .padding(.top, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(spacing: 16) {
            HStack {
                QuietButton("Back", minHeight: 44, action: dismiss)
                Spacer()
                Text("Data")
                    .font(.system(.headline, design: .rounded))
            }
            Spacer()
            Text("Exports stay on this device unless you choose where to save them.")
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
            Spacer()
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
            Text("This permanently deletes your current local Flowmo data. This cannot be undone.")
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
    @FocusState private var captureFocused: Bool

    var body: some View {
        PhaseColumn {
            if controller.showCapture, !status.isPaused {
                HairlineField("Park a thought", text: $controller.captureDraft)
                    .focused($captureFocused)
                    .onSubmit { controller.submitCapture() }
                    .onAppear { captureFocused = true }
            } else {
                PhaseLead(status.intention, cue: "Focus", tone: atmo.mute)
            }
        } hole: {
            Aperture(ring: .none) {
                VStack(spacing: 10) {
                    InstrumentClock(Format.clock(status.elapsed), size: 56)
                        .milestoneGrow(elapsed: status.elapsed, paused: status.isPaused)
                    Accrual(seconds: status.earnedBreakSeconds, label: Format.earned(status.earnedBreakSeconds))
                }
            }
        } verb: {
            if status.isPaused {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            } else if controller.showCapture {
                HStack(spacing: 10) {
                    QuietButton("Discard", minHeight: 44) { controller.discardCapture() }
                    InkButton("Park") { controller.submitCapture() }
                        .disabled(controller.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack(spacing: 12) {
                    QuietButton(parkButtonTitle, minHeight: 44) {
                        controller.showCapture = true
                    }
                    QuietButton("Stop", minHeight: 44) { controller.stopFocus() }
                }
            }
        }
    }

    private var parkButtonTitle: String {
        let count = status.captures.count
        return count == 0 ? "Park thought" : "Park another · \(count)"
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
            }
        }
    }
}

private func ringProgress(_ status: SessionStatus) -> Double {
    guard let duration = status.phaseDuration, duration > 0 else { return 0 }
    return min(1, max(0, status.elapsed / duration))
}
