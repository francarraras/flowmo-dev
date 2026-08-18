# Flowmo v1 — engineering design

This is the **Plan** artifact (2026: architecture, contracts, gaps, how we prove it).  
Locked product: [`PROJECT.md`](PROJECT.md), [`acceptance.md`](acceptance.md).  
Locked constraints: [`plan.md`](plan.md) (SwiftPM window, JSON store, CLI side door, no brand).  
[`tasks.md`](tasks.md) is rewritten from this design after sign-off.

Signed off by the captain on 2026-08-18. Close beat is click-to-dismiss (Skip = dismiss).

Section 1 (state machine) confirmed by the captain on 2026-08-18.
Sections 3 and 5 (JSON store and Core events) confirmed by the captain on 2026-08-18.
Section 4 (modules) confirmed by the captain on 2026-08-18.

---

## 1. Target state machine

Idle is `live == nil`. One live session max.

```
idle --Start--> prime
prime --timeout or Skip--> focus
focus --Stop or Skip--> break
break --timeout or Skip--> recall
recall --timeout or Skip--> closeBeat
closeBeat --click or Skip--> idle
```

**Hide / close window:** no transition. Process keeps running; reopen shows the same phase, still moving.

**Quit or Mac sleep:** `any live phase --> paused(that phase)`. Clock frozen. One Continue. Window appearing does not resume. Continue → same phase, clock runs again.

Paused is a *wrapper*, not a fifth product phase. You are still in prime/focus/break/recall/closeBeat, frozen.

---

## 2. Gaps in the sketch (must change Core)

Today’s `FlowmoCore` is a headless CLI engine. Reuse the store and reducer idea. These behaviors are **wrong** vs acceptance:

| Sketch now | Required |
|---|---|
| States: priming, encoding, paused, onBreak, recall. No idle UI, no close beat. | Idle (`live == nil`) + `closeBeat`. Names in the window: Focus (not “encoding”). |
| Pause only while focusing (`cannotPause` otherwise). Resume always returns to focus. | Quit/sleep pauses **whatever phase** you were in. Continue resumes **that** phase. |
| `finish()` jumps to `live = nil`. | Quiet close beat first (focus time, break time, recall text), then idle. |
| No recall-answer field. | Optional “What did you just do?” text on the snapshot. |
| `profile.lastNote` is a ratio lecture, not the idle intention. | Store `lastIntention` for the idle line. |
| CLI has `pause` / `resume` as user verbs. | That is a pause-during-flow control. Remove from the human CLI. Continue is window recovery only (agents may call the same resume event if we expose it as `continue`, not as a focus pause). |
| `history[]` exists but is unused in the UI. | Keep it internally to compute **today’s** focus total (local midnight). Do not build a history screen. |
| Learner keeps 5 durations, applies last 3. | Last **three** only for the rule (already the apply logic). Fine. |

Do not start a second store to fix these. Change `Engine`.

---

## 3. `world.json` contract

Path: `~/.flowmo/world.json`. Atomic write. Exclusive lock (`world.lock`) around load-mutate-save. Same file for window and CLI.

Logical document (field names may match today’s Codable with additive keys):

- `config` — prime 120s, recall 300s, default ratio 5 (not user-facing in v1).
- `profile.breakRatio`, `profile.recentFocusSeconds` (enough to apply last-3 rule), `profile.lastIntention`.
- `live` — null when idle; else id, intention, `phase` (prime/focus/break/recall/closeBeat), timestamps for phase start, focus start/end, break duration, captures[], optional `recallText`, optional freeze (`pausedAt` + frozen elapsed/remaining so Continue restores the same phase).
- `history` — completed focus/break/recall summaries for today-total and learning. Not shown as a list.

Clock rule: UI displays `now - timestamp` (or frozen values while paused). A 1-second timer must not be the source of truth.

---

## 4. Modules

| Module | Owns | Must not own |
|---|---|---|
| **FlowmoCore** | World, events, lock, JSON, view-model numbers (elapsed, remaining, earned break). | Windows, sound, notifications, SwiftUI. |
| **FlowmoWindow** | Compact SwiftUI frame, state layout, pin (default off), Continue, + capture. | A second clock or a second file. |
| **Flowmo** (executable) | `NSApplication` + host the window. Quit/sleep → Core pause. | Business rules. |
| **FlowmoCLI** | Verbs + `status --json` on Core. Snapshot, not a ticking TUI. | Pause-as-flow, daily human UX. |
| **Adapters** | Phase-change sound; notification if window is background. | Session math. |

The Xcode app (`Apps/Flowmo.xcodeproj`, bundle `app.flowmo.mac`) is another executable that imports `FlowmoWindow` + `FlowmoCore`. Same as `swift run`.

**Window vs CLI liveness:** Window ticks from timestamps and **reloads when `world.json` changes** (file watch). CLI is request/response. Two clocks is a bug.

---

## 5. Events Core must support

- `start(intention)` — idle only.
- `skip` — prime, break, recall, closeBeat; during focus = stop.
- `stopFocus` — focus only → break.
- `capture(line)` — focus (and frozen focus).
- `setRecallText` — recall.
- `pauseForRecovery` — any live phase (quit/sleep). Not a window button.
- `continue` — paused only → same phase.
- `sync(now)` — timeouts: prime→focus, break→recall, recall→closeBeat. Close beat does **not** auto-advance; dismiss/Skip → idle.

Cancel: keep for agents if needed; not on the window in v1 (Stop is the human end-of-focus).

---

## 6. Close beat

Not in the sketch. Plan: stay on a quiet summary (focus duration, break duration, recall text if any) until the user **clicks to dismiss**, then idle. Skip is the same as dismiss. No timer. No score.

---

## 7. Prove it (before calling the slice done)

- Core tests: transitions above; skip=stop in focus; pause any phase + continue same phase; break = focus/ratio; last-3 ratio rule; today total uses local midnight; one live session; close beat stays until dismiss/Skip (no auto-idle).
- If `import XCTest` fails on this Mac, use `flowmo-check` / a SwiftPM test target that *does* compile. Do not wait for full Xcode.
- Manual: `swift run` through the loop once, hide-and-reopen, quit-and-Continue, one CLI `status --json` while the window ticks.

---

## 8. Out of this design

Brand, living terminal, menu bar, iPhone, SQLite, history UI, growing the CLI into the product.
