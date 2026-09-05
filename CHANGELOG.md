# Changelog

Notable changes are recorded here.

## 1.0 (5) — Release candidate

- Restored standard Mac application, Edit, and Window menus, including Quit,
  clipboard editing, Undo/Redo, Close, and Minimize. Quit uses the existing
  recovery path, so reopening still waits for Continue or Restart.
- Refined Mac and iPhone around a quieter graphite-and-ivory instrument:
  standard SF typography, clearer supporting text, restrained champagne for
  earned rest, and crisp rounded-rectangle controls with stable touch targets.
  Focus keeps a steady ivory count-up; the working name remains Flowmo.
- Replaced the faux lunar face, segmented ring assembly, button halos, clock
  milestone growth, and final-seconds pulse with a static graphite well,
  continuous 2pt timed rings, and restrained fades. Focus still has no progress
  ring or deadline, and recovery still waits for Continue or Restart.
- Added original bundled Horizon Study artwork to the native Focus canvases
  and refreshed the same three-page tutorial with illustrations, a step
  indicator, and clearer copy. Its Skip, replay, notification choice, and
  never-auto-start behavior remain intact. Ambient light changes pause when
  the scene is inactive or Reduce Motion is enabled. Integrated the original
  aperture-and-incision icon into the Mac and iPhone catalogs, retaining the
  earlier crescent master as build 4 provenance.
- Improved phone Focus hierarchy, gave its actions persistent subtle surfaces
  and at least 48pt touch height, removed the capture field's fixed height
  ceiling, and made Reflection actions and error/recovery content adapt to
  available space. Current phone targets remain portrait-only. This polish
  is included in build 5; earlier build 4 preview artifacts remain unchanged.
- Kept the terminal executable and bundled artwork together during installation
  and upgrades. Complete payload checksums reject missing or altered resources;
  an interrupted upgrade preserves a usable installed command.
- Added a separate **FlowmoPhoneLocal** build for free Personal Team testing on
  an iPhone. It keeps the session loop and local reminders in its own app
  container without iCloud, App Group, push, or a Home Screen widget. The existing
  entitled phone app keeps its store and recovery rules. Documented the chosen
  no-paid-membership distribution path and Apple's periodic reinstall limit.
- Stacked iPhone recovery controls at accessibility text sizes so Continue
  stays readable without splitting its label.
- Added a read-only Focus Live Activity to Flowmo Local for the Lock Screen and
  supported Dynamic Island. Its clock counts up from the saved Focus timestamp;
  tapping opens the app without resuming recovery. It shares no written session
  text and adds no cloud, push, or Home Screen widget capability. Starting an
  activity requires the app in the foreground; a background Prime ending keeps
  its notification, with the activity starting when the app opens into Focus.
  Stop, recovery, and store errors end the activity when reconciled. iOS controls
  placement and lifetime. This local phone feature is included in the build 5 source;
  Mac archives do not install the iPhone app.

## 1.0 (4) — Readiness candidate

- Added a short, one-time introduction on Mac and iPhone explaining intention,
  open-ended Focus, proportional rest, and the next step. Skip and completion
  remain dismissed on that device; **Data > How it works** replays it. The
  tutorial never starts a session and waits while a session, recovery, or sync
  conflict needs attention. Notification permission is now an explicit choice.
- Fixed Mini windows hiding sync-conflict choices. Recovery and tutorial panes
  temporarily use Classic without overwriting the saved Mini preference.
- Fixed iPhone Retry treating a remotely owned live session as a local crash.
  Phone reminders now schedule both the end of Break and the following
  Reflection boundary, including when the app stays in the background.
- Improved small-screen and larger-text phone layouts, retained text-field focus
  while the keyboard opens, enlarged Idle footer targets, and made Data controls
  scrollable. Improved quiet text and field-placeholder contrast, menu-bar
  readability, Reduce Motion behavior, and the Delete All explanation.
- Added a provisional original app icon for Mac and iPhone. The product name is
  unchanged pending the later branding decision.
- Made CLI help, version, and invalid arguments safe before accessing session
  data. Added literal text argument handling and reliable living-terminal exit
  with Escape, q, Control-C, or process signals, restoring terminal settings.
- Added universal Mac CLI packaging, checksums, and an installer with explicit
  upgrade and overwrite protection. Reworked the README and release guidance
  for GitHub distribution, with MIT prepared for open-source review. No public
  download, donation, or support destination has been invented or published.

- Made returning to **Focus scene** unmistakable after **Back to window**. An
  explicit named Scene action now sits with the live Focus controls in Classic
  and Mini, so re-entry no longer depends on recognizing the sun-and-horizon
  presentation icon; the same Focus and count-up clock continue unchanged.
- Brought Distant Horizon to iPhone. Every active unpaused Focus now fills the
  phone frame with the same ambient gold horizon, intention, honest count-up,
  and earned-rest signal while keeping Park thought and End focus within reach.
  Recovery Pause still returns to the frozen compact aperture with Continue
  and Restart. The horizon adds no Focus deadline, progress ring, session data,
  sync state, permission, or desktop-only window behavior.
- Prevented a delayed private-sync conflict button from choosing a newer
  conflict that replaced the one shown on screen. Conflict choices now carry
  the exact displayed conflict and expire harmlessly when that conflict is no
  longer current.
- Made exact iPhone Continue, Restart, and Done actions commit through one
  World authority. Stale controls now adopt the newer saved Session, and a
  private-sync bookkeeping failure no longer makes a durable local action look
  unsaved; Flowmo keeps the saved result and identifies sync as the problem.
- Prevented private sync from overwriting a newer local action with a cloud
  result computed from stale state. Remote reconciliation now reloads the
  latest local state under the same store transaction and persists the World
  before its corresponding sync metadata while holding one ordered lock lease.
  Conflict choices expire when their cloud facts change, and a stale
  same-session ownership marker can no longer skip Recovery Pause.
- Replaced the temporary Mini preset with a real Mac **Focus scene**. From
  Prime, one action starts the same open-ended Focus inside a borderless,
  movable and resizable Distant Horizon canvas with the intention, count-up
  clock, **End focus**, and **Back to window**. Back restores the prior Classic/Mini and
  pin choices and keeps the exact Focus counting without switching apps. During
  Focus, the sun-and-horizon presentation control now enters or re-enters Scene
  directly; its adjacent menu repeats **Focus Scene** before the Classic/Mini
  choices, so both sides of the control provide a clear way back. The menu
  dismisses before Scene changes the window. This
  removes the ambiguous hidden Scene action and the broken hybrid frame that
  could appear on a second menu-based entry, without resetting the persisted
  clock. End starts the earned Break. A
  recovery pause, replacement, close, or process loss safely discards the
  transient Scene. It adds no session data, permission, system Focus change, or
  lockout.
- Removed the redundant **Use next** hop after a completed session. On Mac and
  iPhone, **Done** now carries that exact session’s explicit next step into the
  editable Idle intention. It never starts automatically, falls back to older
  work, or creates new persisted data; stale cross-surface actions leave the
  winning session untouched. Mini opens Classic so the carried step is visible.
- Made Mac Focus entry frictionless: choosing **Focus now** cooperatively
  returns control to the already-running app the person came from. Automatic
  Prime expiry never switches apps, and a target selected in Focus Guard stays
  closed. The handoff exists only in memory, adds no setup or extra decision,
  and never persists or logs an app identity, URL, file path, window title, or
  browser tab.
- Closed the parked-thought loop: Reflection can now review saved thoughts
  newest-first and turn one into the editable next step without deleting it.
  Mini opens this review in Classic, and iPhone mirrors the same flow.
- Made History actionable on Mac and iPhone. Expanding any completed session
  now offers **Use next step**, or **Use intention** when that is the only cue.
  The choice returns to Idle for confirmation, never starts automatically, and
  asks before replacing an intention already typed there.
- Reworked the visible session loop around Flowmo’s actual advantage: open-ended
  count-up focus and self-directed breaks. A first session now explains the
  model in place; Break says **Take what you need** and advances with **Reflect**.
- Turned Reflection into the concrete prompt **Where will you pick up next?**
  and paid it back at Close and the next Idle. Close now truthfully says
  **Break earned**, shows the next step and parked-thought count, and has a
  visible **Done** action. **Use next** reveals only the newest session’s cue for
  confirmation and never silently falls back to stale work.
- Made capture discoverable as **Park thought**, with the parked count visible
  after capture, and removed Focus Guard measurement explanation from the main
  Idle surface while keeping its explicit export in Data.
- Kept the iPhone session interface quiet when no iCloud account is configured,
  while preserving structural sync failures and deletion problems. Added the
  background notification mode required by `CKSyncEngine`.

## 1.0 (3) — Friends & family preview

- Removed the irrelevant iCloud-unavailable notice from local-only Mac builds while preserving user-actionable sync conflicts and deletion warnings.
- Made earned rest legible on Break by showing the proportional rest beside the Focus duration that earned it.
- Added a fast **Use last** path on Mac and iPhone that reveals the saved intention for confirmation before starting, while keeping Idle empty by default. **New** now clears only the unstarted draft instead of erasing the saved intention.
- Fixed the local Mac executable crashing at launch when CloudKit entitlements are unavailable; unentitled builds now continue in local-only mode.

- Added private CloudKit synchronization between the entitled Mac and iPhone
  apps. Offline changes remain local and queued; distinct completed sessions
  merge, while simultaneous live starts, account changes, resets, and ambiguous
  edits require an explicit choose-one decision before controls continue.
- Kept cross-device recovery honest: a live session received from another
  device is not paused as a local crash, and opening either app never resumes a
  recovery-paused session by itself.
- Made Delete All remove private local sync replicas immediately, queue exact
  CloudKit record deletion, and report incomplete deletion until the cloud
  confirms it. Updated privacy declarations for private iCloud user content and
  product interaction used only for app functionality.
- Raised the supported floor to macOS 14 and iOS 17 for CKSyncEngine.
- Removed automatic break-ratio movement based only on the last three Focus
  durations. Existing valid ratios are preserved; new/reset profiles use 5,
  completed-session totals still update, and no new rolling duration samples or
  ratio-movement reasons are created.
- Sharpened Reflection to **What did you do, and what comes next?** across Mac,
  iPhone, CLI, and the living terminal. It combines concrete retrieval with a
  resumption cue without claiming a memory or productivity benefit.
- Made Prime's existing immediate path explicit with **Focus now** on Mac and
  iPhone. Prime remains an optional settling beat of up to two minutes, and the
  underlying timing and CLI `skip` contract are unchanged.
- Made Break neutral and explicitly self-directed: the caption is now **Break**
  and the existing early-exit action is labeled **Continue** on Mac and iPhone.
  The earned proportional countdown and CLI `skip` contract are unchanged.
- Added the WP3 Focus Guard resumption implementation. After **Stay focused**
  commits, Flowmo can reactivate the exact prior unguarded process instance and
  counts it as confirmed only when the matching activation notification arrives
  within one second. Missing identity, rejection, and timeout preserve the prior
  safe behavior; any resolution or activation identity mismatch disables the
  new treatment for the process lifetime without disabling baseline Guard.
- Froze the aggregate-only `focus_guard_resumption_v1` engineering plan and its
  optional supervised 60-attempt field-audit rule. It uses a new evidence
  schema/plan and does not merge pre-WP3 counts.
- Added a repository-only `flowmo-wp3-gate` evaluator for chronological start
  and end exports. It rejects malformed, incomplete, saturated, mismatched, or
  integrity-affected runs and does not create or upload treatment attempts.
- Replaced the month-long owner-testing blocker with an automated 60-cycle
  pipeline proof covering Guard, exact-process confirmation, aggregate storage,
  exports, and gate evaluation. The 30-day rule remains only an optional field
  audit maximum; one real-app success and safe fallback stay in release smoke.
- Added the WP2 local instrumentation foundation on Mac. Focus Guard records
  only six bounded aggregate path counts in a separate store: prompt offered
  after confirmed hide, Stay focused chosen, Open once chosen, activation
  accepted, Open once not accepted, and interception failed before a prompt.
- Instrumentation writes are ordered off the main thread, use fail-fast locks,
  have a fixed 16-write admission bound, contain no private session or app
  identity data, and cannot reject or alter a product action. The explicit Focus
  Guard counts export states that completeness is unknown, raw rates are invalid,
  and no learning, productivity, well-being, or causal claim is supported.
  Delete All Data removes the counts.
- Kept the Focus Guard counts explanation behind a quiet info control instead of
  occupying the calm Idle interface.
- Recovery-paused sessions now reject other loop mutations until the user
  chooses Continue or Restart; CLI callers receive `recovery_paused`, while cue
  preference and presentation controls remain available.
- Focus Guard now uses the documented “Stay focused” action in both Mac views.

## 1.0 (2) — Friends & family preview

- Kept the Guard switch and deletion notices inside the idle chrome so they no
  longer sit on each other or draw past the window.
- Dropped Guard Off/On copy; the switch is the on/off, and the label only names
  Guard or the app count.
- Stabilized the shared phase chrome so bottom controls are not pushed outside
  the Mac or phone layout.

## 1.0 (1) — Initial friends & family preview

- Added a versioned JSON CLI contract and structured action responses.
- Hardened local-store reads, validation, atomic writes, quarantine, export,
  exact non-recursive deletion, numeric handling, and terminal rendering against
  malformed input and control-sequence injection.
- Hardened Focus Guard identity and retry handling while preserving its
  fail-open, hide-only behavior.
- Made Mac quit/sleep recovery transactional, made a kernel-held lifetime lock
  authoritative over forgeable JSON metadata, and cleared stale session
  metadata after terminal transitions and deletion.
- Persisted a Continue recovery boundary so an immediate CLI Continue followed
  by a Mac crash cannot erase already-frozen elapsed or remaining time.
- Made post-launch lifecycle failures expand a Mini window to the full recovery
  pane and return to Mini after a successful retry.
- Deferred session completion until Close is accepted, so Restart and Cancel
  after recovery do not create history or adapt the break ratio.
- Added privacy-safe diagnostics, full-data export, confirmed deletion, and
  explicit recovery paths to the Mac and iPhone apps.
- Added the iPhone and widget privacy manifest for local App Group file-metadata
  access, declaring no tracking or collected data.
- Made a missing iPhone App Group an explicit unavailable state instead of
  silently creating a second fallback store; the widget matches that state.
- Added XCTest targets, CLI privacy/integration smoke tests, and warning-as-error
  Mac/iPhone/widget CI build and analysis coverage.
- Documented private-beta privacy, security, and release boundaries.
- Added an explicitly labeled Mac-only friends-and-family preview package path
  with per-app Gatekeeper instructions and archive integrity checks.
