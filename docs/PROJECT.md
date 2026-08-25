# Flowmo — product

This is the source of truth for the **current** product. It replaces the iPhone MVP vision in `~/Flowmo` (January–April 2026) for all new work.

If a sentence here conflicts with the old repo, the old App Store launch plan, or the sketch CLI in this folder, **this file wins**.

Last updated: 2026-08-24
Owner: Fran Carrara  
Status: 1.0 close-beta candidate; external Apple distribution remains gated.

---

## 1. What Flowmo is now

Flowmo is a Flowmodoro inspired by Barbara Oakley’s practical learning
principles, research on habit and attention, and the owner’s experience. It
provides an open-ended focus ritual; it does not claim that one timer pattern is
universally optimal for learning or productivity.

You work until **you** stop (count up). You rest in proportion to how long you actually focused. Before focus you still; after the break you briefly recall. While you work you can park a thought without leaving. The tool stays light and fast. The public face is a compact native window on Mac and the same privately synced loop on iPhone. Power users and scripts can inspect and fire supported verbs through the versioned CLI contract; they do not replace the app or write the store directly.

**Working copy:** Stop counting down. Start flowing up. The product name and
tagline are placeholders; branding is not a roadmap dependency.

**One-line test:** if it feels like another 25/5 timer, it failed. If you need a setup wizard or a command list to start focusing, it also failed.

---

## 2. What it is not

- A generic Pomodoro (fixed 25/5, countdown as the main act)
- The old iPhone app grown sideways (Home, five tabs, score screen, flashcards, App Store hardening)
- A terminal you drive command-by-command (`start`, then `status`, then `skip`, then `stop`)
- A menu-bar chip as the product (a glance may come later)
- A dashboard, streak game, or social app

---

## 3. Why it exists (updated vision)

Rigid Pomodoro can interrupt work at an arbitrary deadline. Flowmodoro
(Flowtime) inverts that relationship: the person chooses when Focus ends.
Flowmo combines that core with ideas popularized by Oakley / *Learning How to
Learn*, habit research, and the owner’s experience without putting a protocol
lecture in front of the clock.

Those sources are design inputs, not proof that Flowmo’s complete loop improves
learning. The implementation must match a studied intervention before it
inherits that intervention’s claim.

| Design input | Current Flowmo translation | Evidence stance |
|---|---|---|
| Focus and disengagement | Open-ended Focus, then a break | A break creates an opportunity to disengage; it does not prove a discrete “diffuse mode” or an optimal break dose. |
| Process and autonomy | Count **up**; the person chooses when to Stop or Skip | A product value and behavior hypothesis, not proof of greater productivity or flow. |
| Stable starting cue | Up-to-two-minute Prime with the chosen intention | A settling ritual. Two minutes is a hypothesis; Focus now remains available. |
| Cognitive offloading | One-line Capture during Focus | A low-friction convenience that may prevent a switch; the current form has no learning claim. |
| Retrieval and resumption cue | Optional post-break Reflection: “What did you do, and what comes next?” | It asks for concrete retrieval and a next step, but has no proven retention or resumption effect. |
| Situation design | Optional, fail-open Focus Guard | Precommitted friction is plausible; benefit and stress or autonomy costs must be tested in Flowmo. |
| Proportional recovery | `break = focus / ratio`, with a fixed per-profile ratio | A transparent product heuristic. New/reset profiles use 5; no evidence establishes that dose as cognitively optimal. |

Evidence rules for future decisions:

- A neural mechanism such as neuroplasticity does not by itself establish a
  product outcome.
- A whole-loop claim requires a Flowmo-specific comparison and the relevant
  delayed or behavioral outcome.
- Test one mechanism at a time. Before implementation, freeze the construct,
  operational definition, denominator, comparator, observation window,
  missingness rule, benefit, harm, meaningful threshold, stopping rule, and
  uncertainty analysis.
- Session duration, fewer bypasses, or repeated app use are not automatically
  learning, well-being, or productivity gains.

WP2 shipped privacy-bounded instrumentation plumbing on Mac, not a study result.
It uses a separate `evidence.json`, not `world.json`, so instrumentation failure
cannot invalidate the session store. A serial utility queue preserves local
event order without doing file I/O on the product actor; export and deletion
drain pending writes, and cross-process lock contention fails fast.

WP3 extends that plumbing under the new, frozen `focus_guard_resumption_v1`
plan. It retains the original six operational paths and adds aggregate-only
resumption eligibility and terminal outcomes. The pre-WP3 plan is not merged
into this one.

| Counter | Exact trigger | What it does not prove |
|---|---|---|
| Prompt offered | The selected app is confirmed hidden, then Flowmo requests foreground presentation | That the prompt was visible or seen |
| Stay focused chosen | Stay focused first clears a current interception | That focus resumed or improved |
| Open once chosen | An Open once path reaches either accepted or not accepted; recorded atomically with that outcome | Why the person chose it |
| Activation accepted | macOS returns success for activation of the same PID + bundle ID + launch identity | That the app became frontmost or the prior document/window returned |
| Open once not accepted | The exact identity no longer resolves or macOS declines its activation request | Whether macOS received a request, a user harm, or a productivity loss |
| Interception failed before prompt | Identity resolution or hiding fails and Guard commits fail-open before offering a prompt | Any rate; it is only a raw technical count |
| Resumption eligible / ineligible | After Stay focused commits, the remembered prior unguarded PID + bundle ID + launch identity does or does not still resolve | A useful work context or document |
| Resumption treatment disabled | Stay focused commits after an earlier mismatch disabled WP3 for the process lifetime | That baseline Guard is unavailable |
| Resumption request accepted / rejected | macOS accepts or rejects one request for the exact eligible process instance | Foreground activation |
| Resumption confirmed | A matching activation notification arrives within one second | A restored window, document, or cognitive context |
| Resumption timed out | No non-Flowmo activation notification arrives within one second | Why activation was not observed |
| Resolution / activation identity mismatch | Resolution returns a different identity, or the first non-Flowmo activation notification names a different identity | User intent; either mismatch disables the treatment for the process lifetime |

It stores no typed text, session identifier, app identity, PID, bundle
identifier, path, raw duration, or event timestamp, and it has no network
client, analytics SDK, or automatic upload. Recording completeness is unknown:
the recorder accepts at most 16 outstanding writes and drops overflow, and
counters saturate at the maximum declared in the export. Counts are therefore
only possibly saturated lower bounds on paths successfully observed by this
recorder, not rates or estimates of actual technical-event volume.

A valid planned comparison uses predeclared start and end exports from the same
local store and frozen plan, with the start actually before the end, increasing
`generatedAt`, no intervening deletion/reset/store replacement, and no end
counter below its start. A counter at the declared cap is censored and has no
exact delta. `generatedAt` is export time, not event time. These counts cannot
establish learning, productivity, well-being, or causal Focus Guard benefit.

Any code change that can alter event eligibility, emission timing, signal
meaning, atomic mapping, recorder admission/drop policy, or the counter/buffer
caps must mint a new measurement-plan identifier before collection. Counts from
different plans must never be merged.

WP3 implementation acceptance is deterministic and runs in the test suite. A
60-cycle pipeline proof exercises Guard interception, exact-process activation
acceptance and matching notification, typed evidence mapping, the real local
aggregate store, chronological exports, and the fixed evaluator. Every record
must be accepted and all 60 attempts must reconcile as confirmed with zero
failure. The proof does not exercise macOS foreground policy, so one real-app
success and the safe fallback remain ordinary release smoke checks.

The same 60-attempt, 95% reliability and one-sided 95% exact confidence rule is
retained as an optional field audit, not a roadmap or owner-testing blocker. Its
30-day window is a maximum collection interval, never a required wait. Any
identity mismatch, unsafe fallback, counter saturation, known recorder drop,
store/export problem, process crash, nonmatching snapshot, or incomplete
eligible-to-terminal reconciliation rejects or invalidates that audit. Raw
unsupervised counts cannot pass it, and neither automated nor field technical
evidence supports a focus, productivity, or well-being claim.

Evidence anchors for those boundaries:

- One 94-student, two-hour comparison found no overall differences in endpoint
  productivity, task completion, flow, motivation, or fatigue. Motivation
  declined faster under both Flowtime and Pomodoro than under self-regulated
  breaks, and fatigue rose faster under Pomodoro; this supports testing break
  autonomy, not validating or invalidating Flowmo’s whole loop
  ([study](https://pmc.ncbi.nlm.nih.gov/articles/PMC12292963/)).
- Retrieval practice has robust classroom evidence when people retrieve defined
  material and later learning is tested
  ([systematic review](https://pubmed.ncbi.nlm.nih.gov/33683913/)).
- Incubation effects exist but vary with the problem, preparation, interruption,
  and intervening task
  ([meta-analysis](https://doi.org/10.1037/a0014212)).
- Micro-breaks show small average benefits for vigor and fatigue, but not a
  reliable overall performance benefit
  ([meta-analysis](https://doi.org/10.1371/journal.pone.0272460)).
- Habit formation depends on repeated behavior in stable contexts and varies
  widely by person and behavior; a short ritual is not itself a formed habit
  ([systematic review](https://pmc.ncbi.nlm.nih.gov/articles/PMC11641623/)).
- Experience-dependent neuroplasticity is real, but even neural measurements
  can be transient or ambiguous; it cannot serve as a proxy for a Flowmo outcome
  ([systematic review](https://pubmed.ncbi.nlm.nih.gov/42105826/)).
- An exploratory one-week field study of 32 information workers used largely
  self-assessed outcomes and found heterogeneous focus, workload, and stress
  responses to blocking. It supports keeping Guard optional, reversible, and
  fail-open—not prioritizing Guard as a proven focus intervention
  ([field study](https://www.microsoft.com/en-us/research/publication/effects-individual-differences-blocking-workplace-distractions/)).

Spaced repetition, flashcards, consolidation protocols, long-form reflection,
flow scores, and streaks are **not** in this version. They can return later as
optional depth. They are not the identity of the app.

The product must stay:

- **A — Lightweight and instant.** Compact window. One frame. Seconds to start.
- **B — Easy, configurable if you want.** Defaults are enough. The CLI is the supported automation boundary; the local file remains inspectable internal storage.
- **C — Scriptable.** CLI and JSON support integrations without becoming the daily UI.
- **D — A real app for Mac and iPhone.** The native session frame is what people use.

---

## 4. The v1 loop (locked)

You type **once**. That line is the intention. Prime does not ask again.

1. **Idle → type (or keep last line) → Start**
2. **Prime — up to 2:00** — still with that line on screen. Focus now whenever ready.
3. **Focus — count up** — work until you stop. **+** parks one line. No pause button.
4. **Stop → earned break** — `break = focus / ratio`. Default ratio **5** (50 min focus → 10 min break). Continue whenever ready.
5. **Reflection — 3:00** — “What did you do, and what comes next?” Optional lines. Skip allowed.
6. **Quiet close beat** — focus time, break taken, anything you wrote — then idle again.

Encoding (focus) is the only required open-ended phase. Prime and recall have ends. Break is **not** a protocol phase in the old sense; it is the earned interlude between focus and recall.

Timed beats always have an advance action: **Focus now** on Prime, **Continue**
on Break, and **Skip** on Reflection. The CLI keeps the stable `skip` verb for
all three. Skip during Focus is the same as Stop (you have chosen to end Focus).

---

## 5. The window (locked)

The Mac **window is the product**.

- **One surface.** Same compact frame. The insides change. No Home, no tabs, no setup-then-another-app.
- **Size.** Two fixed modes, not a free-resize document. **Classic** is 320×460 and holds the full instrument. **Mini** is 168×176 — aperture plus the current verb. Mode persists.
- **Always on top.** Off by default. One control to pin over your work.
- **Look.** Not designed yet. Do not invent a new brand in the first implementation pass unless asked. The old iPhone app was black + cyan; that is a *reference*, not a mandate.

### States

| State | On screen | Actions |
|---|---|---|
| **Idle** | Empty field, placeholder **Intention**. **Start**. Today, **History**, **Data**, **New**. | Type a line, Start, inspect history, export/delete data, or New (clears a typed line). |
| **Prime (up to 2:00)** | Intention + **Prepare**. Countdown + **determinate** ring. | Settle, or Focus now whenever ready. |
| **Focus** | Intention + **Focus**. **Big count-up clock**. Gold strip + “Xm earned”. **+** opens capture; **Park** / **Discard** replace + / Stop. | Work. Park a thought. Stop. |
| **Break** | Neutral **Break** caption. Recommended countdown + determinate gold ring. | Rest, or Continue whenever ready. |
| **Reflection (3:00)** | **What did you do, and what comes next?** Optional text. Countdown + ring. | Write, sit, or skip. |
| **Close beat** | Intention. Two labeled clocks: Focused and Rested. No score, no share. | Tap the frame. Then idle. |

### Focus visual (important)

Count-up has no finish line. A 0–100% “progress” ring during focus is a **lie** (that is Pomodoro). Do not add one.

- Timed phases (prime, break, recall) → real ring/bar that has an end.
- Focus → big clock + **earned-break strip** (information: rest you are accruing).

This is the “on steroids” visual that is still honest.

### Capture

Not an always-visible field. A small **+** on the focus state opens one line. Enter parks it and clears. The lines stay on the session in **History**. No sheet, no categories in v1 (distraction vs idea can be inferred later; don’t ask now).

### Pause

**No Pause button** while working. You are in, or you Stop (and earn the break).

Pause exists only as **recovery**:

- Quit the app, or the Mac sleeps → on return the session is **paused**.
- On return: same phase, clock frozen, **Continue** or **Restart**. Bringing the window forward does not resume. Continue resumes from the frozen time. Restart drops the frozen session (not recorded) and starts Prime with the same line.
- While recovery-paused, Continue and Restart are the only actions that may
  mutate the session. Skip, Stop, capture, recall edits, Cancel, and close-beat
  dismissal are rejected. Mute and presentation-only controls remain available
  and never resume the session.
- A persisted Continue boundary protects the frozen clock even when Continue is
  sent through the CLI immediately before a Mac crash.
- Only one Mac process may own recovery for a store. A kernel-held lifetime lock
  is authoritative; the JSON marker is crash metadata, not proof that an owner
  is alive. A competing Mac window blocks mutations and offers Retry.

### Window lifetime

- Hide or close the window: session **keeps running**. Reopen and you are in the same state.
- Quit / sleep: restore **paused**.
- There is only **one** live session.

### Sound and attention

- Soft cues **on by default** at phase changes (prime ended, you stopped, break ended, recall ended).
- If the window is in the background: **sound + a system notification**. Clicking the banner brings the window forward.
- Mute is a compact-window control. Default is audible. Mute silences the phase sound; background banners still post.

---

## 6. Surfaces and who they’re for

| Surface | Role in v1 | Role later |
|---|---|---|
| **Mac window** | The product | Still the product |
| **Menu bar** | Glance only (clock; click shows the window) | Still not the product |
| **Terminal living view** | `flowmo live` ticks the same session | Still a view, not the product |
| **CLI / JSON** | Scripts and integrations | Same verbs, same store as the window |
| **iPhone** | Shipped ([`iphone.md`](iphone.md)) | Same loop and private CloudKit session |
| **Widgets** | Shipped ([`widget.md`](widget.md)) | Glance; not the product |

### CLI and scripts

Humans do not run a session by typing `start` → `status` → `skip` → `stop`. That was a mistake in an early sketch.

Scripts may fire verbs against the same session shown by the window or living terminal view:

- start with a label  
- stop focus  
- skip current timed beat  
- continue or restart a recovery-paused session
- capture a line  
- save recall text
- cancel the current session
- status as JSON  
- later: supported ratio configuration verbs; the ratio does not move automatically

Action and error responses use a documented versioned JSON envelope and do not
echo private session text. `status --json` is the explicit read contract when a
script needs those session fields. The internal `world.json` schema is not a
write contract. While recovery-paused, other action verbs return
`recovery_paused` without changing the frozen session.

The API talks to the **same** live session as the window. Two clocks is a bug.

### Data and diagnostics

Data controls are deliberately reachable only from Idle. A full export is a
validated snapshot of the user's local data. A redacted diagnostic export
contains app/build/OS metadata, phase and counts, and stable issue codes with
operation categories and timestamps—never intention, capture, recall,
selected-app identifiers, or store paths.

On Mac, a separate explicit Focus Guard counts export contains only the
versioned aggregate instrumentation report described above. It does not
silently join the full-data or diagnostic export, and no export uploads itself.

Invalid stores are never silently discarded. The recovery action preserves the
original bytes before resetting. **Delete All Data** requires explicit
confirmation, refuses a live session, and removes the canonical data and exact
Flowmo-owned recovery artifacts without recursively deleting a planted
directory. On Mac it also removes the separate evidence store and its exact
owned recovery artifacts. Any incomplete cleanup remains visible to the user;
the app must not claim all data was deleted if either cleanup is incomplete.

### Private cross-device sync

The entitled Mac and iPhone apps synchronize the loop through the user's
private `iCloud.app.flowmo` CloudKit database. The shared state is the live
session, fixed break ratio, resumption intention, and completed history. Cue
preference, Focus Guard configuration, local evidence, lifecycle markers, and
widget/App Group mechanics stay on their device.

Each device remains usable offline. Completed sessions with distinct IDs merge;
two offline live starts, an account change, or any other ambiguous concurrent
edit blocks session controls behind an explicit **Keep this device** / **Use
iCloud version** choice. Flowmo never silently merges two live sessions. A live
session received from another device is not treated as a local process crash
and is not recovery-paused merely because the receiving app opens.

Cloud work is queued durably without storing content hashes or logging private
text. Switching iCloud accounts never uploads the old account's pending private
data to the new account without a choice. Delete All removes local private
replicas immediately, queues deletion of the CloudKit records, and reports
incomplete deletion until CloudKit confirms it. The iPhone widget remains a
glance over the phone App Group copy and never controls or directly syncs a
session.

---

## 7. Fixed break ratio (current behavior)

Break remains `focus / ratio`. New and reset profiles use ratio **5** (50 min
Focus → 10 min Break). Flowmo does not change the ratio from session duration:
duration says nothing about fatigue, break quality, task type, learning, or
whether the person felt restored.

Existing valid persisted ratios are preserved to avoid silently changing a
tester's established break length. Completing a session still records history,
session count, and total Focus, but it does not move the ratio, append a rolling
duration sample, or create a ratio-movement note. Legacy rolling samples remain
readable for store compatibility and are not extended.

Prime stays 2:00. Reflection stays 3:00. The current profile ratio remains
inspectable through `status --json`; `ratioReason` is absent because there is no
automatic movement to explain. The idle window does not need a lecture about it.

---

## 8. Numbers and names

| Thing | Value | Notes |
|---|---|---|
| Prime | 120 s | Focus now allowed |
| Focus | open | Count up |
| Break | `focus / ratio` | Ratio starts at 5 |
| Reflection | 180 s | Skip allowed |
| Intention | one string | Typed at idle; shown through prime |
| Today line | sum of completed focus today | Local midnight; idle only |
| Storage ids | stable tokens (`encoding`, `writing`) | Not display strings like `"Deep Code"` |
| Clock | computed from timestamps | Not a 1-second UI timer as source of truth |

`intensityMultiplier` existed in the old app and was **never applied**. Do not invent an intensity formula in v1.

---

## 9. What we keep from the old iPhone app

Keep as **ideas and numbers**, not as a codebase to extend:

- Count-up focus, you stop
- `break = encoding / ratio` (tested path: 600 s / 5 = 120 s)
- Prime 2 min, reflection 3 min
- Park a thought mid-session
- Dark compact session energy (reference only)
- Tagline shape; “Flowmo” remains a working placeholder, not a branding decision

Leave behind:

- Home, Session Setup screens, five tabs
- Forced multi-phase protocol as the default path
- Consolidation, reflection sheets, flow score, SM-2 flashcards
- SwiftData + `SessionManager` as the engine (`Timer`, notifications, UI flags, persistence in one `@MainActor` class)
- App Store screenshot/launch program as current work
- Display-string enums (`"Deep Code"`, `"Active Recall"`) as storage
- Menu bar or CLI as the thing you *live* in

Old tree (frozen reference): `/Users/facspro/Flowmo`  
GitHub: `https://github.com/francarraras/Flowmo` (private)

---

## 10. What is on disk in *this* folder

`/Users/facspro/dev/flowmo` is the current close-beta implementation: the
deterministic Core, native Mac window, Focus Guard, supporting glances and CLI,
iPhone app, private CloudKit sync, widget, recovery paths, and privacy controls.
The Mac window is the product; the CLI remains a side door.

macOS on this machine is case-insensitive: `~/flowmo` and `~/Flowmo` are the **same path**. New work must stay under `~/dev/flowmo` (or another name that is not `Flowmo`).

Core proofs use `swift run flowmo check` (`import XCTest` / `import Testing` may fail without full Xcode). The Dock `.app` is a thin Xcode host of the same window (`Apps/Flowmo.xcodeproj`, bundle `app.flowmo.mac`); `swift run` remains the SwiftPM launcher.

---

## 11. Technical direction (current)

The current implementation follows this shape:

1. **One logical session**, persisted as timestamped local replicas plus a private CloudKit replica. Elapsed time is `now - startedAt`. Break remaining is `endsAt - now`. Any UI is a view. The separate Mac evidence file contains aggregates only and is never session authority.
2. **One live session per local store**, with a file lock shared by the Mac window and CLI. Cross-device ambiguity becomes an explicit conflict; it never becomes two silently merged Focus sessions.
3. **Native session frames** on Mac and iPhone. Menu bar, terminal, CLI, and widget remain supporting views.
4. Do **not** start by opening a new Xcode clone of `~/Flowmo`.
5. Persistence: a small local JSON store plus durable private-sync metadata. SwiftData is not required.
6. Notifications and sound are adapters around phase transitions, not the engine.

The shipped loop remains **idle → prime → focus → break → recall → close beat → idle**, with recovery pause, supporting glances, and a local completed-session list.

---

## 12. Later (explicitly not v1)

- Visual identity / themes beyond the shipped compact pass
- Menu bar as the product (glance is in [`menu-bar.md`](menu-bar.md))
- Watch and Live Activities
- Flashcards, SM-2, consolidation protocols, or long-form reflection
- History dashboard, scoring, or charts
- Domain-specific learning protocols such as spaced repetition, content testing,
  or interleaving
- Monetization, licensing, marketing (out of scope for this brief)

Roadmap: [`v2.md`](v2.md).

---

## 13. Decision log

Made with the owner in conversation, 2026-08-17 → 2026-08-18.

| Decision | Choice |
|---|---|
| Science lineage | Oakley, habit and attention research, and owner experience guide hypotheses; claims remain evidence-bounded. |
| Start | Setup then prime; do not drop the fundamentals |
| Type intention | Once, at idle. Prime only displays it. |
| After focus | Earned break, then short recall |
| Capture in v1 | Yes, one line, via **+** |
| First place it lives | Mac, **real window** as the main thing |
| Window structure | One frame, states change |
| Prime | Intention + stilling (2:00) |
| Reflection | Question + optional lines (3:00) |
| Focus visual | Big clock + thin earned-break strip and “Xm earned” |
| Timed-phase visual | Determinate ring/bar |
| Fake 0–100% focus bar | No |
| Menu bar | Glance only ([`menu-bar.md`](menu-bar.md)). Window stays the product. |
| Terminal | `flowmo live` is a ticking view. Verbs stay a side door. |
| Automatic adjustment in v1 | None. Preserve an existing valid profile ratio; new/reset profiles use 5. |
| Window size | Two fixed modes: Classic 320×460, Mini 168×176. No free resize. |
| Pin default | Off |
| Look | Compact pass in [`visual.md`](visual.md) (black + cyan reference). Not a theme pack. |
| Idle | Empty Intention + Start + today + History + Data + New (clears a typed line) |
| Sound | Soft cues **on** by default |
| Background phase end | Sound + system notification |
| Close / hide window | Session keeps running |
| Quit / sleep | Restore **paused** |
| Resume after quit / sleep | **Continue** or **Restart**. Window appearing does not resume. Restart primes the same intention. |
| Pause button | No |
| After recall | Quiet close beat; tap the frame (Skip = dismiss). Then idle |
| History UI | Local list from Idle. Collapsed: intention, date, focus clock, writing count. Tap expands that session: Focused / Rested, parked lines, reflection. |
| Window delivery | SwiftPM launcher (`swift run`) plus thin Xcode wrap of the same window (`Apps/Flowmo.xcodeproj`, bundle `app.flowmo.mac`) |
| Session store | JSON at `~/.flowmo/world.json` with a file lock |
| Store recovery | Preserve invalid bytes before reset; never silently replace them |
| Data controls | Idle-only full export, redacted diagnostics, confirmed Delete All |
| Mini | Aperture + verb. Mute and pin on the left, expand on the right. Typing expands to Classic. |
| Guide | Process names the beat: Prepare / Focus / Break / Reflection. |

---

## 14. Project checklist

The repository should make these facts clear:

1. Read this file and describe the loop and the window without looking at chat.
2. Ignore `~/Flowmo` except for the formula and the old timer/break screens as visual reference.
3. Ignore the sketch CLI as UX.
4. Implement the compact Mac window against a timestamped session store.
5. Keep CLI/JSON as a side door to that same store.
6. Not add Home, scores, flashcards, or a 25-minute countdown unless the owner reopens those decisions.

For product behavior, start here rather than in the frozen old repo.
