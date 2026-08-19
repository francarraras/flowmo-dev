# Flowmo — standing contract

This file is house law for every coding session. Product intent lives in [`docs/PROJECT.md`](docs/PROJECT.md). If they conflict, **this file and PROJECT.md win** over the sketch CLI in this folder, `~/Flowmo`, and chat memory.

## Process (hybrid)

Default is lean: this file + PROJECT.md, a human-reviewed plan, then implementation.

When a slice will not fit in a short spec — more than one focused page of new behavior, or it would change the locked v1 loop — stop. Write specify → plan → tasks artifacts and get a human gate before code. Do not invent that machinery for a small change.

Signed by the captain on 2026-08-18. Clarify, constraints, engineering Plan (`docs/design.md`), and Tasks (`docs/tasks.md`) are signed. First slice may be implemented only as that task list.

## Always

- Flowmo is a Flowmodoro: count **up**, the user stops. If it feels like a 25/5 countdown timer, it failed.
- The Mac **window is the product**. CLI/JSON may talk to the same live session; they are not the daily UI.
- The intention is typed **once**, at idle. Prime only displays it.
- Timed phases (prime, break, recall) may use a determinate ring. Focus must not.

## Never (without an explicit captain reopen)

- Do not add a Pause button during focus. Quit or sleep restores paused with one Continue; that is recovery, not a flow control. Window appearing must not resume by itself.
- Do not add a 0–100% progress ring during focus.
- Do not add Home, tabs, setup screens, scores, streaks, flashcards, or a v1 menu bar.
- Do not grow the sketch CLI in this repo into the app. Reuse store or reducer ideas if they still fit; throw away command-by-command UX.
- Do not invent a visual brand or theme pack. Look is undecided; the old iPhone black + cyan is reference only.
- Do not start from or extend `~/Flowmo`. Formula and old timer/break screens are reference only.
- Do not add iPhone, widgets, a history browser, or learning beyond the locked break-ratio rule, in v1.

## Not frozen here

Exact SwiftUI pixel look: this pass is signed in [`docs/visual.md`](docs/visual.md) (tighten, black + cyan reference, hide title keep traffic lights). Not a theme pack. Pin default off.

## Source of truth

Read `docs/PROJECT.md` before changing product behavior. Checkable v1 lines: `docs/acceptance.md`. Constraints: `docs/plan.md`. Engineering plan: `docs/design.md`. First slice: `docs/tasks.md`. `docs/V1.md` is superseded.

## Run

- Window: `swift run` (product `flowmo`)
- Dock app: `xcodebuild -project Apps/Flowmo.xcodeproj -scheme Flowmo -configuration Release CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES` then open `Flowmo.app` (bundle `app.flowmo.mac`). Same `FlowmoWindow` / Core as `swift run`. Ad-hoc sign; no Apple Developer team.
- Same live session, side door: `swift run flowmo status --json` and the other verbs
- Core proofs: `swift run flowmo check`
- Store: `~/.flowmo/world.json` (override with `FLOWMO_HOME`)

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
