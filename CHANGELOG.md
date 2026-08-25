# Changelog

All notable changes to this private beta are recorded here.

## Unreleased

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
