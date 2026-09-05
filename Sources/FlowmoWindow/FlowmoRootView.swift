import AppKit
import FlowmoCore
import FlowmoLook
import FlowmoSync
import SwiftUI
import UniformTypeIdentifiers

enum FocusSceneEntryControl {
    static let title = "Focus scene"
    static let compactTitle = "Scene"
    static let accessibilityLabel = "Open Focus Scene"
    static let accessibilityHint =
        "Opens the same Focus in Scene. The menu also offers Focus Scene and window sizes."

    static func isAvailable(phase: SessionPhase?, isPaused: Bool) -> Bool {
        phase == .focus && !isPaused
    }

    static func parkTitle(captureCount: Int) -> String {
        captureCount == 0 ? "Park thought" : "Park · \(captureCount)"
    }
}

struct FlowmoRootView: View {
    @ObservedObject var controller: FlowmoSessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = controller.status
        let atmo = Atmosphere.of(status)
        let introduction = controller.introduction.isPresented && controller.canShowIntroduction
        let focusScene =
            controller.isFocusSceneActive
            && !controller.storeNeedsRecovery
            && !controller.lifecycleNeedsRecovery
            && controller.syncStatus.conflict == nil
        let mini =
            controller.displayMode == .mini
            && !controller.storeNeedsRecovery
            && !controller.lifecycleNeedsRecovery
            && controller.syncStatus.conflict == nil
            && !introduction
        let size = controller.effectiveWindowContentSize
        Group {
            if focusScene {
                DistantHorizonScene(controller: controller, status: status)
            } else if controller.storeNeedsRecovery {
                StoreRecoveryPane(controller: controller)
            } else if let conflict = controller.syncStatus.conflict {
                SyncConflictPane(controller: controller, conflict: conflict)
            } else if controller.lifecycleNeedsRecovery {
                LifecycleRecoveryPane(controller: controller)
            } else if introduction {
                IntroductionView(
                    state: controller.introduction,
                    onRequestNotifications: controller.requestNotifications
                )
            } else if mini {
                MiniView(controller: controller, status: status)
            } else if status.isIdle {
                IdlePane(controller: controller, status: status)
            } else {
                phasePane(status)
            }
        }
        .padding(.horizontal, focusScene ? 0 : (mini ? 6 : 16))
        .padding(.bottom, focusScene ? 0 : (mini ? 8 : 14))
        .padding(.top, focusScene ? 0 : (mini ? 26 : 28))
        .frame(
            minWidth: focusScene ? 0 : size.width,
            maxWidth: focusScene ? .infinity : size.width,
            minHeight: focusScene ? 0 : size.height,
            maxHeight: focusScene ? .infinity : size.height
        )
        .foregroundStyle(atmo.ink)
        .background(FieldCanvas())
        .environment(\.atmosphere, atmo)
        .animation(reduceMotion ? nil : Motion.phase, value: status.isPaused)
        .animation(reduceMotion ? nil : Motion.phase, value: controller.displayMode)
        .animation(reduceMotion ? nil : Motion.phase, value: focusScene)
        .onAppear { controller.presentIntroductionIfNeeded() }
        .onChange(of: controller.canShowIntroduction) { _, _ in
            controller.presentIntroductionIfNeeded()
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topLeading) {
            if mini, !focusScene {
                HStack(spacing: 0) {
                    muteButton(atmo, compact: true)
                    pinButton(atmo, compact: true)
                }
                .padding(.leading, 52)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !focusScene, !introduction, !controller.storeNeedsRecovery, !controller.lifecycleNeedsRecovery {
                HStack(spacing: 0) {
                    if mini {
                        presentationControl(status: status, compact: true)
                            .padding(.trailing, 4)
                    } else {
                        muteButton(atmo)
                            .opacity(atmo.chrome)
                        pinButton(atmo)
                            .opacity(atmo.chrome)
                        presentationControl(status: status)
                            .opacity(canEnterFocusScene(status) ? 1 : atmo.chrome)
                            .padding(.trailing, 8)
                    }
                }
            }
        }
        .background(WindowPin(pinned: controller.isPinned, field: atmo.field, focusSceneActive: focusScene))
        .alert(item: $controller.activeIssue) { issue in
            Alert(
                title: Text(issue.title),
                message: Text("\(issue.message)\n\nIssue code: \(issue.code.rawValue)"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func canEnterFocusScene(_ status: SessionStatus) -> Bool {
        FocusSceneEntryControl.isAvailable(phase: status.phase, isPaused: status.isPaused)
    }

    @ViewBuilder
    private func presentationControl(status: SessionStatus, compact: Bool = false) -> some View {
        if canEnterFocusScene(status) {
            Menu {
                Button {
                    DispatchQueue.main.async {
                        controller.enterFocusScene()
                    }
                } label: {
                    Label("Focus Scene", systemImage: "sun.horizon")
                }

                Divider()
                windowPresentationChoices()
            } label: {
                ChromeGlyph("sun.horizon", lit: true, compact: compact)
            } primaryAction: {
                controller.enterFocusScene()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help(FocusSceneEntryControl.accessibilityLabel)
            .accessibilityLabel(FocusSceneEntryControl.accessibilityLabel)
            .accessibilityHint(FocusSceneEntryControl.accessibilityHint)
            .padding(.top, compact ? 6 : 4)
        } else {
            Menu {
                windowPresentationChoices()
            } label: {
                ChromeGlyph("rectangle.3.group", compact: compact)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change window size")
            .accessibilityLabel("Change window size")
            .padding(.top, compact ? 6 : 4)
        }
    }

    @ViewBuilder
    private func windowPresentationChoices() -> some View {
        Button {
            controller.setDisplayMode(.classic)
        } label: {
            Label(
                "Classic window",
                systemImage: controller.displayMode == .classic ? "checkmark" : "rectangle"
            )
        }
        .disabled(controller.displayMode == .classic)

        Button {
            controller.setDisplayMode(.mini)
        } label: {
            Label(
                "Mini window",
                systemImage: controller.displayMode == .mini ? "checkmark" : "rectangle.inset.filled"
            )
        }
        .disabled(controller.displayMode == .mini)
    }

    private func muteButton(_ atmo: Atmosphere, compact: Bool = false) -> some View {
        let on = controller.world.config.cuesEnabled
        return Button {
            controller.setCuesEnabled(!on)
        } label: {
            ChromeGlyph(on ? "speaker.wave.2" : "speaker.slash", lit: on, compact: compact)
        }
        .buttonStyle(PressStyle())
        .help(on ? "Mute cues" : "Unmute cues")
        .accessibilityLabel(on ? "Mute cues" : "Unmute cues")
        .padding(.top, compact ? 6 : 4)
    }

    private func pinButton(_ atmo: Atmosphere, compact: Bool = false) -> some View {
        let actionLabel = controller.isPinned ? "Unpin" : "Pin on top"
        return Button {
            controller.togglePin()
        } label: {
            ChromeGlyph(controller.isPinned ? "pin.fill" : "pin", lit: controller.isPinned, compact: compact)
        }
        .buttonStyle(PressStyle())
        .help(actionLabel)
        .accessibilityLabel(actionLabel)
        .padding(.top, compact ? 6 : 4)
        .padding(.trailing, compact ? 0 : 8)
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

private struct SyncConflictPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    let conflict: WorldSyncConflict

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Choose what to keep")
                .font(.system(.title2, design: .default).weight(.semibold))
            Text(message)
                .font(.system(.body, design: .default))
                .foregroundStyle(atmo.mute)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                InkButton("Keep this device") {
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
            "Two sessions were started offline. This device has \(summary(conflict.local)); iCloud has \(summary(conflict.remote))."
        case .initialImport:
            "This device and iCloud both contain Flowmo data. Nothing will be overwritten until you choose."
        case .resetGeneration:
            "One copy was reset while the other changed. Choose the complete copy you want to keep."
        case .profile, .completedSession:
            "This device and iCloud changed the same Flowmo data. Choose the copy you want to keep."
        }
    }

    private func summary(_ snapshot: WorldSyncSnapshot) -> String {
        guard let live = snapshot.head.live else { return "no active session" }
        let intention = live.intention.trimmingCharacters(in: .whitespacesAndNewlines)
        return intention.isEmpty ? "an active session" : "“\(intention)”"
    }
}

private struct IdlePane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
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
                    sessions: HistoryOrder.newestFirst(controller.world.history),
                    hasCurrentDraft: !controller.intentionDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty,
                    resume: { session, replacingCurrentDraft in
                        controller.resumeCompletedSession(
                            session,
                            replacingCurrentDraft: replacingCurrentDraft
                        )
                    },
                    dismiss: { showingHistory = false }
                )
            } else {
                PhaseColumn {
                    FlowField(
                        "Intention",
                        text: $controller.intentionDraft,
                        autofocus: true,
                        focusDelay: 0.45,
                        onSubmit: {
                            guard canStart else { return }
                            performIdleAction()
                        }
                    )
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
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
                    .help(idleActionHelp)
                } chrome: {
                    VStack(spacing: 8) {
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
                        .font(.system(.caption, design: .default).weight(.medium))
                        GuardConfig(controller: controller)
                        if let notice = controller.userNotice {
                            Text(notice)
                                .font(.system(.caption2, design: .default).weight(.medium))
                                .foregroundStyle(atmo.mute)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { controller.clearNotice() }
                        }
                        if let notice = worldSyncNotice(controller.syncStatus) {
                            Text(notice)
                                .font(.system(.caption2, design: .default).weight(.medium))
                                .foregroundStyle(atmo.mute)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 8)
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

    private var usesNextStep: Bool {
        typedIntention.isEmpty && nextStep != nil
    }

    private var usesLastIntention: Bool {
        typedIntention.isEmpty && nextStep == nil && !savedIntention.isEmpty
    }

    private var canStart: Bool {
        !typedIntention.isEmpty || nextStep != nil || !savedIntention.isEmpty
    }

    private var startButtonTitle: String {
        if usesNextStep { return "Use next" }
        return usesLastIntention ? "Use last" : "Start"
    }

    private var idleActionHelp: String {
        if usesNextStep { return "Show the next step from your last session" }
        if usesLastIntention { return "Show last intention" }
        return "Start this intention"
    }

    private var isFirstRun: Bool {
        controller.world.history.isEmpty
            && controller.world.profile.sessionCount == 0
            && savedIntention.isEmpty
    }

    private func performIdleAction() {
        if usesNextStep {
            controller.useNextStep()
        } else if usesLastIntention {
            controller.useLastIntention()
        } else {
            controller.start()
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
    case "sync_entitlement_unavailable":
        return nil
    default:
        return "iCloud sync is unavailable. Flowmo is working locally."
    }
}

private struct HistoryPane: View {
    @Environment(\.atmosphere) private var atmo
    var sessions: [CompletedSession]
    var hasCurrentDraft: Bool
    var resume: (CompletedSession, Bool) -> Bool
    var dismiss: () -> Void
    @State private var expandedID: UUID?
    @State private var pendingResumption: CompletedSession?
    @State private var showingReplacementConfirmation = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                QuietButton("Back", action: dismiss)
                Spacer()
                Text("History")
                    .font(.system(.headline, design: .default))
            }
            if sessions.isEmpty {
                Text("No completed sessions yet.")
                    .font(.system(.body, design: .default))
                    .foregroundStyle(atmo.mute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions, id: \.id) { session in
                            HistorySessionCard(
                                session: session,
                                expanded: expandedID == session.id,
                                resumptionTitle: resumptionTitle(for: session),
                                onResume: { attemptResumption(session) }
                            ) {
                                withAnimation(Motion.phase) {
                                    expandedID = expandedID == session.id ? nil : session.id
                                }
                            }
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
        guard hasCurrentDraft else {
            finishResumption(session, replacingCurrentDraft: false)
            return
        }
        pendingResumption = session
        showingReplacementConfirmation = true
    }

    private func finishResumption(_ session: CompletedSession, replacingCurrentDraft: Bool) {
        if resume(session, replacingCurrentDraft) {
            pendingResumption = nil
            dismiss()
        }
    }
}

private struct PrimePane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseLead(status.intention, cue: "Prepare")
        } hole: {
            Aperture(ring: .timed(progress: ringProgress(status))) {
                InstrumentClock(Format.remainingClock(status.remaining ?? 0))
            }
        } verb: {
            if status.isPaused {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            } else {
                HStack(spacing: 10) {
                    QuietButton("Focus now") { controller.focusNow() }
                        .help(
                            "Starts Focus and returns to your previous work app when available and not guarded"
                        )
                        .accessibilityHint(
                            "Starts Focus and returns to your previous work app when available and not guarded."
                        )
                    InkButton("Focus scene") { controller.startFocusScene() }
                        .help(
                            "Start Focus in a large movable horizon scene"
                        )
                        .accessibilityHint(
                            "Starts the same open-ended Focus in a large movable horizon. Back to window keeps Focus running without switching apps."
                        )
                }
            }
        }
    }
}

private struct FocusPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            if let hit = controller.focusGuard.runtime.interception, !status.isPaused {
                PhaseCaption("\(hit.displayName) is guarded.", tone: atmo.mute)
            } else if controller.showCapture, !status.isPaused {
                FlowField(
                    "Park a thought",
                    text: $controller.captureDraft,
                    autofocus: true,
                    focusDelay: 0.12,
                    onSubmit: { controller.submitCapture() },
                    onCancel: { controller.discardCapture() }
                )
            } else {
                VStack(spacing: 6) {
                    PhaseLead(status.intention, cue: "Focus", tone: atmo.mute)
                    if let guardStatus = controller.guardStatusLine {
                        PhaseCaption(guardStatus, tone: atmo.faint)
                    }
                }
            }
        } hole: {
            Aperture(ring: .none) {
                VStack(spacing: 10) {
                    InstrumentClock(Format.clock(status.elapsed), size: 52)
                    Accrual(seconds: status.earnedBreakSeconds, label: Format.earned(status.earnedBreakSeconds))
                }
            }
        } verb: {
            if controller.focusGuard.runtime.interception != nil, !status.isPaused {
                HStack(spacing: 12) {
                    QuietButton("Stay focused") { controller.stayFocused() }
                    InkButton("Open once") { controller.openOnce() }
                }
            } else if status.isPaused {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            } else if controller.showCapture {
                HStack(spacing: 10) {
                    QuietButton("Discard") { controller.discardCapture() }
                    InkButton("Park") { controller.submitCapture() }
                        .disabled(controller.captureDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack(spacing: 8) {
                    QuietButton(parkActionTitle) {
                        controller.showCapture = true
                    }
                    .help("Save a thought without leaving Focus")
                    QuietButton(FocusSceneEntryControl.title) {
                        controller.enterFocusScene()
                    }
                    .help(FocusSceneEntryControl.accessibilityLabel)
                    .accessibilityHint(FocusSceneEntryControl.accessibilityHint)
                    QuietButton("Stop") { controller.stopFocus() }
                }
            }
        }
    }

    private var parkActionTitle: String {
        FocusSceneEntryControl.parkTitle(captureCount: status.captures.count)
    }
}

private struct StoreRecoveryPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    @State private var exportingDiagnostics = false
    @State private var diagnosticDocument: FlowmoJSONDocument?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Data needs attention")
                .font(.system(.title3, design: .default).weight(.semibold))
            Text("Flowmo couldn’t read its local data. Retry, or preserve the original and reset.")
                .font(.system(.body, design: .default))
                .foregroundStyle(atmo.mute)
                .multilineTextAlignment(.center)
            Text(FlowmoIssueCode.storeUnreadable.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(atmo.faint)
            HStack(spacing: 12) {
                QuietButton("Retry") { controller.retryStore() }
                InkButton("Preserve & Reset") { controller.preserveAndResetStore() }
            }
            QuietButton("Export Redacted Diagnostics") {
                guard let data = controller.prepareDiagnosticExport() else { return }
                diagnosticDocument = FlowmoJSONDocument(data: data)
                exportingDiagnostics = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileExporter(
            isPresented: $exportingDiagnostics,
            document: diagnosticDocument,
            contentType: .json,
            defaultFilename: FlowmoExportKind.diagnostics.defaultFilename
        ) { result in
            switch result {
            case .success:
                controller.exportFinished(kind: .diagnostics, succeeded: true)
            case .failure(let error):
                if !FlowmoExportResult.isUserCancellation(error) {
                    controller.exportFinished(kind: .diagnostics, succeeded: false)
                }
            }
            diagnosticDocument = nil
        }
    }
}

private struct LifecycleRecoveryPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    @State private var exportingDiagnostics = false
    @State private var diagnosticDocument: FlowmoJSONDocument?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Recovery needs attention")
                .font(.system(.title3, design: .default).weight(.semibold))
            Text("Flowmo couldn’t safely protect quit or sleep recovery. Retry before continuing.")
                .font(.system(.body, design: .default))
                .foregroundStyle(atmo.mute)
                .multilineTextAlignment(.center)
            Text(FlowmoIssueCode.recoveryUnavailable.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(atmo.faint)
            InkButton("Retry") { controller.retryLifecycleRecovery() }
            QuietButton("Export Redacted Diagnostics") {
                guard let data = controller.prepareDiagnosticExport() else { return }
                diagnosticDocument = FlowmoJSONDocument(data: data)
                exportingDiagnostics = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileExporter(
            isPresented: $exportingDiagnostics,
            document: diagnosticDocument,
            contentType: .json,
            defaultFilename: FlowmoExportKind.diagnostics.defaultFilename
        ) { result in
            switch result {
            case .success:
                controller.exportFinished(kind: .diagnostics, succeeded: true)
            case .failure(let error):
                if !FlowmoExportResult.isUserCancellation(error) {
                    controller.exportFinished(kind: .diagnostics, succeeded: false)
                }
            }
            diagnosticDocument = nil
        }
    }
}

private struct DataControlsPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var dismiss: () -> Void
    @State private var showingDeleteConfirmation = false
    @State private var exporting = false
    @State private var exportKind: FlowmoExportKind = .data
    @State private var exportDocument: FlowmoJSONDocument?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    QuietButton("Back", action: dismiss)
                    Spacer()
                    Text("Data")
                        .font(.system(.headline, design: .default))
                }
                Spacer()
                Text("Exports stay on this device unless you choose where to save them.")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(atmo.mute)
                    .multilineTextAlignment(.center)
                InkButton("Export Flowmo Data") {
                    beginExport(kind: .data)
                }
                QuietButton("Export Redacted Diagnostics") {
                    beginExport(kind: .diagnostics)
                }
                QuietButton("Export Focus Guard Counts") {
                    beginExport(kind: .evidence)
                }
                Text(
                    "Best-effort descriptive counts only—no app identities, learning outcomes, or productivity outcomes."
                )
                .font(.system(.caption2, design: .default))
                .foregroundStyle(atmo.faint)
                .multilineTextAlignment(.center)
                QuietButton("Delete All Data") {
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
                    .font(.system(.caption, design: .default))
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
                "This permanently deletes Flowmo data on this Mac, including Focus Guard counts, and removes its synced iCloud copy when one exists. Other synced devices receive that deletion. If you’re offline, iCloud deletion stays pending. This cannot be undone."
            )
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportKind.defaultFilename
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

    private func beginExport(kind: FlowmoExportKind) {
        let data: Data?
        switch kind {
        case .data:
            data = controller.prepareFullDataExport()
        case .diagnostics:
            data = controller.prepareDiagnosticExport()
        case .evidence:
            data = controller.prepareEvidenceExport()
        }
        guard let data else { return }
        exportKind = kind
        exportDocument = FlowmoJSONDocument(data: data)
        exporting = true
    }
}

private struct BreakPane: View {
    @ObservedObject var controller: FlowmoSessionController
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
                    InstrumentClock(Format.remainingClock(status.remaining ?? 0))
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
                QuietButton("Reflect") { controller.skip() }
            }
        }
    }
}

private struct RecallPane: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus
    @State private var parkedIndex = 0

    var body: some View {
        PhaseColumn {
            if status.isPaused {
                PhaseCaption(status.recallText.isEmpty ? "Reflection" : status.recallText, tone: atmo.mute)
            } else if controller.showParkedReview {
                PhaseLead("Parked thoughts", cue: "Choose what comes next", tone: atmo.mute)
            } else {
                FlowField(
                    FlowmoCopy.reflectionPrompt,
                    text: $controller.recallDraft,
                    centered: true,
                    autofocus: true,
                    focusDelay: 0.55,
                    onSubmit: { controller.skip() }
                )
                .onChange(of: controller.recallDraft) { _, _ in
                    controller.persistRecall()
                }
            }
        } hole: {
            Aperture(ring: .timed(progress: ringProgress(status))) {
                if controller.showParkedReview, let selectedParkedThought {
                    ParkedThoughtReview(
                        text: selectedParkedThought.text,
                        position: parkedIndex + 1,
                        count: parkedThoughts.count,
                        onPrevious: { moveParkedIndex(by: -1) },
                        onNext: { moveParkedIndex(by: 1) }
                    )
                } else {
                    InstrumentClock(Format.remainingClock(status.remaining ?? 0))
                }
            }
        } verb: {
            if status.isPaused {
                RecoveryVerbs(
                    onRestart: { controller.restartSession() },
                    onContinue: { controller.continueSession() }
                )
            } else if controller.showParkedReview, let selectedParkedThought {
                HStack(spacing: 10) {
                    QuietButton("Back") { controller.endParkedReview() }
                    InkButton("Use as next") {
                        controller.useParkedThoughtAsNext(selectedParkedThought)
                    }
                }
            } else if canReviewParkedThoughts {
                HStack(spacing: 10) {
                    QuietButton(reviewParkedTitle) { beginParkedReview() }
                    QuietButton(recallActionTitle) { controller.skip() }
                }
            } else {
                QuietButton(recallActionTitle) { controller.skip() }
            }
        }
        .onChange(of: status.isPaused) { _, paused in
            if paused {
                controller.endParkedReview()
            }
        }
    }

    private var recallActionTitle: String {
        controller.recallDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Skip"
            : "Done"
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

    private func beginParkedReview() {
        parkedIndex = 0
        controller.beginParkedReview()
    }

    private func moveParkedIndex(by offset: Int) {
        guard !parkedThoughts.isEmpty else { return }
        parkedIndex = min(max(parkedIndex + offset, 0), parkedThoughts.count - 1)
    }
}

private struct CloseBeatPane: View {
    @ObservedObject var controller: FlowmoSessionController
    var status: SessionStatus

    var body: some View {
        PhaseColumn {
            PhaseCaption(status.intention.isEmpty ? "Close" : status.intention, tone: Look.mute)
        } hole: {
            Aperture(ring: .none) {
                VStack(spacing: 10) {
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
                QuietButton("Done") { controller.dismissCloseBeat() }
                    .keyboardShortcut(.defaultAction)
                    .help(closeActionHelp)
                    .accessibilityHint(closeActionHelp)
            }
        }
    }

    private var closeActionHelp: String {
        status.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Finish this session"
            : "Finish this session and carry the next step into Idle for editing. Focus does not start."
    }
}

private func ringProgress(_ status: SessionStatus) -> Double {
    guard let duration = status.phaseDuration, duration > 0 else { return 0 }
    return min(1, max(0, status.elapsed / duration))
}

private struct GuardConfig: View {
    @Environment(\.atmosphere) private var atmo
    @ObservedObject var controller: FlowmoSessionController

    var body: some View {
        let config = controller.world.config.focusGuard
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    controller.showGuardConfig.toggle()
                } label: {
                    Text(guardLabel(config))
                        .font(.system(.caption, design: .default).weight(.medium))
                        .underline(false)
                        .modifier(QuietHoverInk())
                }
                .buttonStyle(PressStyle())
                Toggle(
                    "On",
                    isOn: Binding(
                        get: { config.enabled },
                        set: { controller.setGuardEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(atmo.mute)
            }
            if controller.showGuardConfig {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(config.bundleIdentifiers, id: \.self) { id in
                            HStack {
                                Text(displayName(id))
                                    .font(.system(.caption, design: .default))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    controller.removeGuardedApp(bundleIdentifier: id)
                                } label: {
                                    Text("Remove")
                                        .font(.system(.caption, design: .default).weight(.medium))
                                        .underline(false)
                                        .modifier(QuietHoverInk())
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }
                }
                .frame(maxHeight: 72)
                QuietButton("Add app") { pickApp() }
            }
        }
    }

    private func guardLabel(_ config: FocusGuardConfiguration) -> String {
        let n = config.bundleIdentifiers.count
        if n == 0 { return "Guard" }
        return n == 1 ? "Guard: 1 app" : "Guard: \(n) apps"
    }

    private func displayName(_ id: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
            let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        {
            return name
        }
        return id
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { result in
            guard result == .OK else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier {
                    controller.addGuardedApp(bundleIdentifier: id)
                }
            }
        }
    }
}

private struct WindowPin: NSViewRepresentable {
    var pinned: Bool
    var field: Color
    var focusSceneActive: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !focusSceneActive else { return }
        guard let window = nsView.window else { return }
        window.level = pinned ? .floating : .normal
        window.hidesOnDeactivate = false
        window.backgroundColor = NSColor(field)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isOpaque = true
        window.appearance = NSAppearance(named: .darkAqua)
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
