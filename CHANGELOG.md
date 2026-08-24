# Changelog

All notable changes to this private beta are recorded here.

## Unreleased

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
