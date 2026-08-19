[~/dev/flowmo/AGENTS.md#04DD]
1:# Flowmo — standing contract
2:
3:This file is house law for every coding session. Product intent lives in [`docs/PROJECT.md`](docs/PROJECT.md). If they conflict, **this file and PROJECT.md win** over the sketch CLI in this folder, `~/Flowmo`, and chat memory.
4:
5:## Process (hybrid)
6:
7:Default is lean: this file + PROJECT.md, a human-reviewed plan, then implementation.
8:
9:When a slice will not fit in a short spec — more than one focused page of new behavior, or it would change the locked v1 loop — stop. Write specify → plan → tasks artifacts and get a human gate before code. Do not invent that machinery for a small change.
10:
11:Signed by the captain on 2026-08-18. Clarify, constraints, engineering Plan (`docs/design.md`), and Tasks (`docs/tasks.md`) are signed. First slice may be implemented only as that task list.
12:
13:## Always
14:
15:- Flowmo is a Flowmodoro: count **up**, the user stops. If it feels like a 25/5 countdown timer, it failed.
16:- The Mac **window is the product**. CLI/JSON may talk to the same live session; they are not the daily UI.
17:- The intention is typed **once**, at idle. Prime only displays it.
18:- Timed phases (prime, break, recall) may use a determinate ring. Focus must not.
19:
20:## Never (without an explicit captain reopen)
21:
22:- Do not add a Pause button during focus. Quit or sleep restores paused with one Continue; that is recovery, not a flow control. Window appearing must not resume by itself.
23:- Do not add a 0–100% progress ring during focus.
24:- Do not add Home, tabs, setup screens, scores, streaks, or flashcards. A status-item glance is allowed ([`docs/menu-bar.md`](docs/menu-bar.md)); it is not the product.
25:- Do not grow the sketch CLI in this repo into the app. Reuse store or reducer ideas if they still fit; throw away command-by-command UX.
26:- Do not invent a visual brand or theme pack. Look is undecided; the old iPhone black + cyan is reference only.
27:- Do not start from or extend `~/Flowmo`. Formula and old timer/break screens are reference only.
28:- Do not add iPhone, widgets, a history browser, or learning beyond the locked break-ratio rule, in v1.
29:
30:## Not frozen here
31:
32:Exact SwiftUI pixel look: signed in [`docs/visual.md`](docs/visual.md). Pin default off. Phase cues on by default; speaker control mutes the sound.

Focus Guard is signed in [`docs/focus-guard-tasks.md`](docs/focus-guard-tasks.md). Do not escalate to Accessibility or a helper if hide() fails.

Menu-bar glance: [`docs/menu-bar.md`](docs/menu-bar.md). Window stays the product. Keep shipping unless the captain names a stop.
33:
34:## Source of truth
35:
36:Read `docs/PROJECT.md` before changing product behavior. Checkable v1 lines: `docs/acceptance.md`. Constraints: `docs/plan.md`. Engineering plan: `docs/design.md`. First slice: `docs/tasks.md`. `docs/V1.md` is superseded.
37:
38:## Run
39:
40:- Window: `swift run` (product `flowmo`)
41:- Dock app: `xcodebuild -project Apps/Flowmo.xcodeproj -scheme Flowmo -configuration Release CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES` then open `Flowmo.app` (bundle `app.flowmo.mac`). Same `FlowmoWindow` / Core as `swift run`. Ad-hoc sign; no Apple Developer team.
42:- Same live session, side door: `swift run flowmo status --json` and the other verbs; living view: `swift run flowmo live`
43:- Core proofs: `swift run flowmo check`
44:- Store: `~/.flowmo/world.json` (override with `FLOWMO_HOME`)
45:
46:## Maintaining this file
47:
48:Keep this file for knowledge useful to almost every future agent session in this project.
49:Do not repeat what the codebase already shows; point to the authoritative file or command instead.
50:Prefer rewriting or pruning existing entries over appending new ones.
51:When updating this file, preserve this bar for all agents and keep entries concise.