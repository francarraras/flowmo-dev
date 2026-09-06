# Flowmo — product

This is the source of truth for the **current** product. It replaces the iPhone MVP vision in `~/Flowmo` (January–April 2026) for all new work.

If a sentence here conflicts with the old repo, the old App Store launch plan, or the sketch CLI in this folder, **this file wins**.

Last updated: 2026-09-06
Owner: Fran Carrara  
Status: 1.0 (6) release candidate in preparation, including the native polish, separate local iPhone variant, and source-build compatibility fixes found by private GitHub CI. Earlier build 4 and 5 artifacts remain unchanged.

---

## 1. What Flowmo is now

Flowmo is a Flowmodoro inspired by Barbara Oakley’s practical learning
principles, research on habit and attention, and the owner’s experience. It
provides an open-ended focus ritual; it does not claim that one timer pattern is
universally optimal for learning or productivity.

You work until **you** stop (count up). You rest in proportion to how long you actually focused. Before Focus you still; after the Break you briefly reflect. On Mac, choosing **Focus now** can hand control back to the already-running app you came from without persisting or logging its identity or contents. While you work you can park a thought without leaving. The tool stays light and fast. The public face is a compact native window on Mac and the same loop in a native iPhone frame. The local iPhone variant keeps an independent session; eligible entitled builds can sync privately. Power users and scripts can inspect and fire supported verbs through the versioned CLI contract; they do not replace the app or write the store directly.

**Working copy:** Stop counting down. Start flowing up. The product name and
tagline are placeholders; branding is not a roadmap dependency.

**One-line test:** if it feels like another 25/5 timer, it failed. If you need mandatory setup or a command list to start focusing, it also failed. The short first-use tutorial is skippable.

---

## 2. What it is not

- A generic Pomodoro (fixed 25/5, countdown as the main act)
- The old iPhone app grown sideways (Home, five tabs, score screen, flashcards, App Store hardening)
- A terminal you drive command-by-command (`start`, then `status`, then `skip`, then `stop`)
- A menu-bar chip as the product
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
| Resumption cue | Optional post-break prompt: “Where will you pick up next?” | It leaves a concrete cue for returning, but has no proven productivity or resumption effect in Flowmo. |
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

1. **Idle → type → Start**. After **Done** carries a just-completed session’s explicit next step into the editable field, Start remains a separate confirmation. When no step was carried, **Use next** can reveal the newest explicit cue; otherwise **Use last** can reveal the prior intention. History can also bring any explicitly chosen Completed Session back to Idle for confirmation.
2. **Prime — up to 2:00** — still with that line on screen. Focus now whenever ready. On Mac, **Focus now** hands control back to the already-running app used immediately before Flowmo when one is available and not guarded. **Focus scene** starts the same Focus in the large, movable Distant Horizon canvas. On iPhone, Focus opens in a phone-native Distant Horizon canvas whether Prime ends by action or time.
3. **Focus — count up** — work until you stop. **Park thought** saves one line without leaving Focus. No pause button.
4. **Stop → earned break** — `break = focus / ratio`. Default ratio **5** (50 min focus → 10 min break). Take what you need, then Reflect whenever ready.
5. **Reflection — 3:00** — “Where will you pick up next?” Optional line. If thoughts were parked, review them newest-first and use one as the editable next step. Skip allowed.
6. **Quiet close beat** — focus time, break earned, next step, and parked-thought count — then Done returns to Idle. That exact session’s nonblank next step is already visible and editable there; nothing starts automatically.

Focus is the only required open-ended phase. Prime and Reflection have ends. Break is **not** a protocol phase in the old sense; it is the earned interlude between Focus and Reflection.

Timed beats always have an advance action: **Focus now** on Prime, **Reflect**
on Break, and **Skip** or **Done** on Reflection. The CLI keeps the stable `skip` verb for
all three. Skip during Focus is the same as Stop (you have chosen to end Focus).

---

## 5. The window (locked)

The Mac **window is the product**.

- **One surface.** Same compact frame. The insides change. No Home, no tabs, no setup-then-another-app.
- **Size.** Two persisted fixed modes, not a free-resize document. **Classic** is 320×460 and holds the full instrument. **Mini** is 168×176 — aperture plus the current verb. Focus Scene is a transient large, movable, resizable presentation of the same window, never a third saved mode.
- **Always on top.** Off by default. One control to pin over your work.
- **Look.** The current treatment is defined in [`visual.md`](visual.md): graphite, ivory, restrained champagne rest accents, standard SF type, static instrument geometry, and crisp controls. Original Horizon Study artwork is bundled for the native Focus canvases and illustrated tutorial. The aperture-and-incision icon direction keeps Flowmo as the working name; this is not a theme system or final naming decision.

### First-use tutorial

Mac and iPhone show a short three-page **How it works** tutorial before the
first available Idle on that device. It explains one intention and optional
Prime, count-up Focus and parked thoughts, then proportional rest and an
optional next step, including the default 50-minute Focus / 10-minute Break
example. **Skip** is available on every page. **Set intention** on the last
page returns to Idle; tutorial **Continue** changes pages only. No tutorial
action types an intention, starts or resumes a Session, or changes History.

The illustrated pages are **Make room for one thing.**, **Stay with the work.**,
and **Leave space to return.** A three-part progress indicator names the current
step for accessibility. Decorative examples remain separate from live session
data. The content scrolls at larger text sizes, and optional page motion respects
Reduce Motion.

Skipping or finishing remembers the current tutorial version in a device-local
preference. **Data → How it works** replays it. A live Session, recovery, or
sync conflict takes precedence; an unfinished tutorial waits until safe Idle
and begins again from its first page. Mac temporarily uses Classic for the
tutorial and restores a saved Mini preference afterward. This is guidance in
the same product frame, not a Home, configuration wizard, or new Loop Beat.

The last page offers optional **Enable notifications** with an explanation;
the same action remains in Data. Launching, skipping, and finishing the
tutorial do not request notification permission automatically.

### States

| State | On screen | Actions |
|---|---|---|
| **Idle** | Editable **Intention** field. It is prefilled only when this surface just completed a session with an explicit next step; otherwise it is empty. The first empty store explains count-up focus and earned break inside the aperture. **Start**, or **Use next** / **Use last** when prior work exists. Today, **History**, **Data**, **New**. | Edit and explicitly Start a carried step; reveal and confirm the newest session’s explicit next step (without falling back to a stale older one) or the last intention; choose any Completed Session in History and return its next step—or its original intention—to Idle for confirmation, asking before replacing a typed draft; export/delete data; or New (clears only the typed draft). |
| **Prime (up to 2:00)** | Intention + **Prepare**. Countdown + **determinate** ring. | Settle or choose **Focus now**. On Mac, Focus now cooperatively returns to the prior work app and **Focus scene** instead stays in Flowmo and opens the Distant Horizon canvas. On iPhone, either Prime exit opens the phone Distant Horizon. |
| **Focus** | Intention + **Focus**. **Big ivory count-up clock**. Champagne strip + “Xm earned”. **Park thought** opens capture; **Park** / **Discard** replace Park thought / Stop. After a capture, the action includes the parked count. iPhone places these facts and controls on its Distant Horizon canvas. The Mac Focus controls include a named **Focus scene** action; the sun-and-horizon presentation control opens the same Scene, and its adjacent menu repeats Scene and changes Classic/Mini. | Work. Park a thought. Enter or re-enter Focus Scene on Mac. Change presentation where offered. Stop. |
| **Break** | Neutral **Break** caption and **Take what you need.** Recommended countdown + continuous determinate champagne ring, with the earned rest and source Focus duration stated plainly. | Rest, or Reflect whenever ready. |
| **Reflection (3:00)** | **Where will you pick up next?** Optional text. Countdown + ring. When the session has parked thoughts and the field is empty, **Review N parked** opens a newest-first chooser inside the same frame. | Write and Done, use a parked thought as an editable next step, sit, or Skip. |
| **Close beat** | Intention. **Focused** and **Break earned**, plus the optional next step and parked-thought count. No score, no share. | Done records this session exactly once, then returns to Idle. Its explicit next step is staged there for editing; blank Reflection leaves Idle empty. |

### Focus visual (important)

Count-up has no finish line. A 0–100% “progress” ring during focus is a **lie** (that is Pomodoro). Do not add one.

- Timed phases (Prime, Break, Reflection) → real ring/bar that has an end.
- Focus → steady ivory clock + **earned-break strip** in champagne (information: rest you are accruing).

The graphite aperture remains still. Timed phases use a continuous 2pt track;
Focus never gains a determinate ring. Clock digits can transition, but the
clock does not grow at milestones or pulse during the final seconds of a Break.
Controls keep a stable shape and use tone rather than halos or scaling for
feedback. Reduce Motion removes optional motion.

### Capture

Not an always-visible field. The quiet **Park thought** action on the focus state opens one line. Enter parks it and clears; the action’s count confirms that the thought stayed. During Reflection, the person can review parked lines newest-first and use one as the editable next step; this is non-destructive, so every line also stays on the session in **History**. Mini retains a compact `+` and opens review in Classic. No sheet, no categories in v1 (distraction vs idea can be inferred later; don’t ask now).

### Next-step bridge

When this surface successfully dismisses an exact live Close beat, its nonblank
Reflection next step is staged as the visible, editable Idle intention. It does
not start Prime. It never falls back to the completed intention, an older
session, or whichever History item happens to be newest after a sync race.
Blank Reflection leaves Idle empty. A stale Done action only adopts the winning
store state and cannot advance or bridge a replacement session.

The staged draft is process-local UI state, not a new persisted field. The
durable source remains the completed session in History, so History can always
restore that exact cue; **Use next** can restore it while that session remains
newest. Sync, reload, and launch never manufacture a staged draft. Mini expands
to Classic when it carries a step so the text is visible before Start.

### Work Handoff

The Mac window remembers the most recently active regular app before Start and
binds that exact running app instance to the live session in process memory.
When the person chooses **Focus now** and Prime successfully enters Focus,
Flowmo asks macOS to hand control back to that app. **Focus scene** instead keeps
Flowmo in front. Entering or leaving Scene is presentation-only and never
activates another app. The Focus-now phase transition is durable first; its
activation is best-effort and can never block Focus or produce an error loop.
Automatic Prime expiry never changes the active app. If the remembered app is
selected in Focus Guard, Flowmo does not open something the person asked it to
block.

Neither path adds a field, attachment, permission prompt, or setting. The
handoff never persists or logs an app identity, URL, file path, document title,
window title, browser tab, or content. It is cleared after the Focus-now
activation request, when Prime ends through any other path, or when the bound
session is replaced. Restart can carry it to
the replacement session only within the same process; crash or relaunch recovery
has no target. Close remains one clear **Done** action.

This restores an already-running app, whose own window and document state remain
untouched. It does not inspect or control a particular browser tab or document,
and it must not grow into AppleScript, Accessibility control, clipboard
surveillance, or browser-history inspection.

### Focus Scene

**Focus scene** is the Distant Horizon presentation of the same honest,
open-ended Focus. Its bundled original Horizon Study artwork is ambient, never progress.
A subtle luminance change eases over 14 seconds in each direction only while
the scene is active and Reduce Motion is off. It does not drive a clock.
It has no ring, percentage, deadline, new phase, setup, or claim that work is
locked down.

On Mac, it can be selected when Prime enters Focus or during an already-running
Focus through Classic's named **Focus scene** action, Mini's named **Scene**
action, or the direct sun-and-horizon presentation control. Its adjacent menu
repeats Scene before the Classic/Mini choices. Scene morphs the existing Flowmo
window into a large, borderless, movable and resizable canvas on one display.
The canvas shows only the intention, count-up clock, **End focus**, and **Back
to window**.

Entry remains in Flowmo. **Back to window** restores the exact prior
Classic/Mini frame and pin choice and keeps the same Focus counting. The normal
window's named action and sun-and-horizon control can each re-enter Scene for
that exact Focus. Escape performs Back to window only while the Scene is key.
**End focus** performs the normal Stop and presents the earned Break. Closing
the Scene restores the normal frame and hides Flowmo while Focus continues. If
Focus Guard needs a decision, its **Stay focused** and **Open once** actions
replace the Scene exits so Escape or close cannot bypass the decision.

The Mac Scene snapshot exists only in process memory for one exact unpaused Focus.
Stop, recovery pause, session replacement, display-mode or pin changes, and
process loss discard it safely. Relaunch and recovery Continue use the ordinary
saved presentation and never recreate a Scene. Screen changes reflow the single
canvas; Flowmo never clones it across displays or creates a macOS full-screen
Space. It starts centered with space around it, drags from the empty canvas,
resizes from its edges, and clamps back onto the visible display after a screen
change. Normal **Focus now**, automatic Prime expiry, sync, and merely showing
the window never activate a Scene.

On iPhone, every active unpaused Focus uses an edge-to-edge, phone-native
Distant Horizon inside the one portrait app frame. The current phone targets
support portrait only. It shows **Focus**, the intention, the ivory
timestamp-derived count-up, champagne earned rest, **Park thought**, and
**End focus**. Capture stays on that canvas and replaces the actions with
**Discard** and **Park**. Prime expiry and **Focus now** both arrive there;
there is no separate window choice because iPhone cannot hand off or morph a
movable desktop window. Recovery Pause returns to the compact frozen aperture
with Continue and Restart, while store recovery and sync conflicts replace the
canvas. Background and foreground do not reset the clock or create another
presentation state. Phone Focus actions have at least 48pt touch height;
large-text action layouts stack, capture has room to grow, and constrained
content scrolls above the keyboard. No new flow or session state is introduced.

Focus Scene does not persist or sync, enable Focus Guard, hide or kill another
app, change macOS Focus, use Accessibility or AppleScript, add a helper, or
create new telemetry. Focus Guard remains the separate optional, fail-open
friction layer.

### Recovery Pause

**No Pause button** while working. You are in, or you Stop (and earn the break).

Pause exists only as **recovery**:

- Quit the app, or the Mac sleeps → on return the session is **paused**.
- On return: same phase, clock frozen, **Continue** or **Restart**. Bringing the window forward does not resume. Continue resumes from the frozen time. Restart drops the frozen session (not recorded) and starts Prime with the same line.
- While recovery-paused, Continue and Restart are the only actions that may
  mutate the session. Skip, Stop, capture, Reflection edits, Cancel, and Close Beat
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

- Soft cues **on by default** at phase changes (Prime ended, you stopped, Break ended, Reflection ended).
- Notification permission is requested only after **Enable notifications** in the tutorial or Data. Declining alerts never blocks the loop; previously declined alerts can be changed in system settings.
- If the Mac window is in the background: **sound + a system notification**, when system permission permits. Clicking the banner brings the window forward without resuming recovery.
- Mute is a compact-window control. Default is audible. Mute silences the phase sound; background banners still post.
- iPhone schedules known timed endings from the persisted Session timestamps before suspension. Starting Break schedules both its end and the following Reflection end; early transitions and recovery replace or cancel obsolete requests. Focus has no scheduled end. See [`iphone.md`](iphone.md).

---

## 6. Surfaces and who they’re for

| Surface | Role in v1 | Role later |
|---|---|---|
| **Mac window** | The product | Still the product |
| **Menu bar** | Glance only (clock; click shows the window) | Still not the product |
| **Terminal living view** | `flowmo live` ticks the same session | Still a view, not the product |
| **CLI / JSON** | Scripts and integrations | Same verbs, same store as the window |
| **iPhone** | Native loop implemented; separate local variant in build 5 source ([`iphone.md`](iphone.md)) | Local personal use; private sync remains available in the entitled target |
| **Home Screen widget** | Implemented for the entitled iPhone target ([`widget.md`](widget.md)); excluded from the local variant | Glance; not the product |
| **Focus Live Activity** | Read-only reminder in the build 5 source in Flowmo Local's Dynamic Island and Lock Screen | Glance; never a session controller |

### Current delivery scope

The owner chose GitHub source, local-only Mac/terminal downloads, and free
Personal Team iPhone testing without paid Apple Developer membership. The
separate **Flowmo Local** app uses the `FlowmoPhoneLocal` scheme and bundle
`app.flowmo.phone.local`. Its `Application Support/flowmo/world.json` belongs
only to that app's sandbox. It neither reads nor migrates the entitled phone's
App Group store, and it never starts CloudKit, queues sync, or updates a Home
Screen widget. It has the same Loop, tutorial, local reminders, recovery,
History, and exports, plus the scoped Focus Live Activity below.
This is personal-device testing, not general iPhone download distribution; see
[`release.md`](release.md#free-personal-testing).

The existing `FlowmoPhone` target retains private sync and its read-only widget
for contributors with the necessary signing capabilities. Missing App Group
access remains an unavailable-store error, never an automatic switch to local
storage. The local variant likewise reports unavailable storage instead of
switching stores. Switching app variants does not transfer sessions or History.
The local variant is included in the build 5 source and remains outside the earlier build 4 artifacts. Mac downloads do not contain an iPhone installer.

### Focus Live Activity

The owner requested an ongoing Focus reminder for Flowmo Local. During active,
unpaused Focus, a read-only Live Activity shows the count-up clock on the Lock
Screen and, on supported iPhones, in Dynamic Island. It has no countdown,
progress ring, intention, parked text, or Reflection text. Tapping it opens the
app; it never stops, pauses, starts, or Continues a session.

The app must be foreground to start this local activity. If Prime expires while
the app is in the background, its ordinary notification still arrives; the
Live Activity can begin when the user next opens the app into Focus. The system
renders elapsed time from the persisted Focus timestamp without keeping Flowmo
running. Going to the Home Screen does not pause Focus. A stop, recovery, or
blocked store ends the activity when the app reconciles those facts. The
activity is a display, never session authority; system removal or dismissal
does not stop Focus. Its placement and lifetime remain subject to iOS policy.
See [`iphone.md`](iphone.md#focus-live-activity) for platform limits.

### CLI and scripts

Humans do not run a session by typing `start` → `status` → `skip` → `stop`. That was a mistake in an early sketch.

Scripts may fire verbs against the same session shown by the window or living terminal view:

- start with a label  
- stop focus  
- skip current timed beat  
- continue or restart a recovery-paused session
- capture a line  
- save Reflection text
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
operation categories and timestamps—never Intention, capture, Reflection text,
selected-app identifiers, or store paths.

Data also offers **How it works** and **Enable notifications**. Tutorial
completion is a local presentation preference, outside session exports and
CloudKit; deleting session data does not make the tutorial run again.

On Mac, a separate explicit Focus Guard counts export contains only the
versioned aggregate instrumentation report described above. It does not
silently join the full-data or diagnostic export, and no export uploads itself.

Invalid stores are never silently discarded. The recovery action preserves the
original bytes before resetting. **Delete All Data** requires explicit
confirmation that names the active variant's local data and any synced iCloud
copy, refuses a live session, and removes the canonical data and exact
Flowmo-owned recovery artifacts without recursively deleting a planted
directory. On Mac it also removes the separate evidence store and its exact
owned recovery artifacts. Any incomplete cleanup remains visible to the user;
the app must not claim all data was deleted if either cleanup is incomplete.

In Flowmo Local, export and Delete All cover only that app's own store and
owned recovery copies. Deletion does not contact iCloud or change another
Flowmo app's data. Deleting the app itself removes its sandbox; export first
if the history must be kept. A full export is not an automatic migration path.

### Private cross-device sync

This behavior belongs to eligible entitled builds and is outside the chosen
no-membership delivery scope. Flowmo Local does not enable it, even if the
phone is signed in to iCloud.

The entitled Mac and iPhone apps synchronize the loop through the user's
private `iCloud.app.flowmo` CloudKit database. The shared state is the live
session, fixed break ratio, resumption intention, and completed history. Cue
preference, Focus Guard configuration, local evidence, lifecycle markers, and
widget/App Group mechanics stay on their device. The Mac work handoff is
process memory rather than session data and never enters CloudKit.

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
| Work handoff | zero or one running app | Mac process memory only; consumed by explicit **Focus now**; every other path out of Prime clears it |
| Focus scene | Mac: zero or one exact live Focus; iPhone: the active unpaused Focus | Mac uses a process-local movable-window snapshot; iPhone derives the canvas from current presentation facts. Neither is session data. |
| Today line | sum of completed focus today | Local midnight; idle only |
| Storage ids | stable tokens (`encoding`, `writing`) | Not display strings like `"Deep Code"` |
| Clock | computed from timestamps | Not a 1-second UI timer as source of truth |

`intensityMultiplier` existed in the old app and was **never applied**. Do not invent an intensity formula in v1.

---

## 9. What we keep from the old iPhone app

Keep as **ideas and numbers**, not as a codebase to extend:

- Count-up focus, you stop
- `break = focus / ratio` (tested path: 600 s / 5 = 120 s)
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

`/Users/facspro/dev/flowmo` is the current release-candidate implementation: the
deterministic Core, native Mac window, Focus Guard, supporting glances and CLI,
iPhone app, a separate local iPhone host, optional entitled private
CloudKit sync and widget, recovery paths, and privacy controls.
The Mac window is the product; the CLI remains a side door.

macOS on this machine is case-insensitive: `~/flowmo` and `~/Flowmo` are the **same path**. New work must stay under `~/dev/flowmo` (or another name that is not `Flowmo`).

Core proofs use `swift run flowmo check` (`import XCTest` / `import Testing` may fail without full Xcode). The Dock `.app` is a thin Xcode host of the same window (`Apps/Flowmo.xcodeproj`, bundle `app.flowmo.mac`); `swift run flowmo` remains the SwiftPM launcher.

---

## 11. Technical direction (current)

The current implementation follows this shape:

1. **One logical session per store**, persisted with timestamps. Entitled sync connects local replicas to a private CloudKit replica; Flowmo Local's store is independent. Elapsed time is `now - startedAt`. Break remaining is `endsAt - now`. Any UI is a view. The optional Mac work-app handoff exists only in window-process memory and is never session authority. The separate Mac evidence file contains aggregates only and is never session authority.
2. **One live session per local store**, with a file lock shared by the Mac window and CLI. Cross-device ambiguity becomes an explicit conflict; it never becomes two silently merged Focus sessions.
3. **Native session frames** on Mac and iPhone. Menu bar, terminal, CLI, and widget remain supporting views.
4. Do **not** start by opening a new Xcode clone of `~/Flowmo`.
5. Persistence: a small local JSON store, with durable private-sync metadata in sync-capable builds. Flowmo Local uses the local authority without sync metadata. SwiftData is not required.
6. Notifications and sound are adapters around phase transitions, not the engine.

The shipped Loop remains **Idle → Prime → Focus → Break → Reflection → Close Beat → Idle**, with Recovery Pause, supporting glances, and local History.

---

## 12. Later (explicitly not v1)

- Theme packs or alternate themes beyond the current visual treatment
- Menu bar as the product (glance is in [`menu-bar.md`](menu-bar.md))
- Watch and Live Activities beyond Flowmo Local's scoped Focus reminder
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
| Start | Type once in Idle, then Prime; do not drop the fundamentals |
| Confirm intention | Enter or edit it once in Idle. A carried next step remains editable there. Prime only displays it. |
| After Focus | Earned Break, then short Reflection |
| Capture in v1 | Yes, one line, via **Park thought** (compact `+` in Mini) |
| Work handoff | Mac remembers the already-running app used before Flowmo only in process memory; explicit **Focus now** returns immediately |
| Focus scene | Mac: explicit large movable Distant Horizon for one exact Focus, restoring Classic/Mini and pin afterward. iPhone: phone-native Distant Horizon for every active unpaused Focus, retaining Park and End controls. |
| First place it lives | Mac, **real window** as the main thing |
| Window structure | One frame, states change |
| Prime | Intention + stilling (2:00) |
| Reflection | One concrete next-step question + optional line (3:00); parked thoughts can become the editable next step |
| Focus visual | Big clock + thin earned-break strip and “Xm earned” |
| Timed-phase visual | Determinate ring/bar |
| Fake 0–100% focus bar | No |
| Menu bar | Glance only ([`menu-bar.md`](menu-bar.md)). Window stays the product. |
| Terminal | `flowmo live` is a ticking view. Verbs stay a side door. |
| Automatic adjustment in v1 | None. Preserve an existing valid profile ratio; new/reset profiles use 5. |
| Window size | Two fixed modes: Classic 320×460, Mini 168×176. No free resize. |
| Pin default | Off |
| Look | Graphite, ivory, restrained champagne, standard SF, and static instrument geometry in [`visual.md`](visual.md). Original shared Horizon Study artwork; working name unchanged. Not a theme pack. |
| Idle | Editable Intention + Start; an exact just-completed next step may already be staged; first-run promise; Use next before Use last; today + History + Data + New (clears only the draft) |
| Sound | Soft cues **on** by default |
| Background phase end | Sound + system notification |
| Close / hide window | Session keeps running |
| Quit / sleep | Restore **paused** |
| Resume after quit / sleep | **Continue** or **Restart**. Window appearing does not resume. Restart primes the same intention. |
| Pause button | No |
| After Reflection | Quiet Close Beat with Next Step and Parked Thought payoff; visible Done. Then Idle |
| History UI | Local list from Idle. Collapsed: intention, date, focus clock, writing count. Tap expands that session: Focused / Break earned, parked lines, next step, and an explicit return action that fills Idle without auto-starting. |
| Window delivery | SwiftPM launcher (`swift run flowmo`) plus thin Xcode wrap of the same window (`Apps/Flowmo.xcodeproj`, bundle `app.flowmo.mac`) |
| Session store | JSON at `~/.flowmo/world.json` with a file lock |
| Store recovery | Preserve invalid bytes before reset; never silently replace them |
| Data controls | Idle-only full export, redacted diagnostics, confirmed Delete All |
| Mini | Aperture + verb. Mute and pin on the left, presentation control on the right. Typing expands to Classic. |
| Guide | Process names the beat: Prepare / Focus / Break / Reflection. |
| First-use explanation | Three skippable pages once per device preference; replay from Data; defer during live/recovery/conflict; return to editable Idle without starting. |
| Notification permission | Explicit Enable notifications in the tutorial or Data, never an automatic launch prompt. |

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
