# Flowmo — project handoff

This is the source of truth for the **current** product. It replaces the iPhone MVP vision in `~/Flowmo` (January–April 2026) for all new work.

If a sentence here conflicts with the old repo, the old App Store launch plan, or the sketch CLI in this folder, **this file wins**.

Last updated: 2026-08-19  
Owner: Fran Carrara  
Status: brief locked; Mac shipped. iPhone slice signed ([`iphone-tasks.md`](iphone-tasks.md)). Widgets, history, theme packs, and iCloud stay after that.

---

## 1. What Flowmo is now

Flowmo is a Flowmodoro — a Pomodoro with the science left in — that gets more accurate to the person using it.

You work until **you** stop (count up). You rest in proportion to how long you actually focused. Before focus you still; after the break you briefly recall. While you work you can park a thought without leaving. The tool stays light and fast. The public face is a compact native window (Mac first, iPhone later). Power users and agents can read and tweak the same session; they do not *be* the session.

**Tagline (kept):** Stop counting down. Start flowing up.

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

Rigid Pomodoro fights flow: it stops you when you are in it, and holds you when you are not. Flowmodoro (Flowtime) inverts that. Flowmo keeps that core and adds the learning science the first iPhone prototype was built around — Oakley / *Learning How to Learn* — without putting a protocol in front of the clock.

| Idea | What it means in Flowmo |
|---|---|
| Focused vs diffuse | Open-ended focus, then a real break |
| Process, not product | Count **up**. You choose when to stop. |
| Prime | Two minutes to still, with the intention already chosen |
| Park the intrusion | One-line capture during focus |
| Active recall | After the break: “What did you just do?” |
| Adaptation | The **break ratio** shifts from your recent sessions |

Spaced repetition, flashcards, consolidation, written reflection, flow scores, and streaks are **not** in this version. They can return later as optional depth. They are not the identity of the app.

The product must stay:

- **A — Lightweight and instant.** Compact window. One frame. Seconds to start.
- **B — Easy, configurable if you want.** Defaults are enough. A file/API exists for people and agents who want knobs.
- **C — Scriptable.** CLI/API so power users and the community can improve it. Not the daily UI.
- **D — Agent-friendly.** An agent can start, read, and tweak the **same** live session the window shows.
- **E — A real app for Mac (then iPhone).** Trendy, visual, “pomodoro on steroids.” The window is what strangers use.

---

## 4. The v1 loop (locked)

You type **once**. That line is the intention. Prime does not ask again.

1. **Idle → type (or keep last line) → Start**
2. **Prime — 2:00** — still with that line on screen. Skip allowed.
3. **Focus — count up** — work until you stop. **+** parks one line. No pause button.
4. **Stop → earned break** — `break = focus / ratio`. Default ratio **5** (50 min focus → 10 min break). Skip allowed.
5. **Recall — 5:00** — “What did you just do?” Optional lines. Skip allowed.
6. **Quiet close beat** — focus time, break taken, anything you wrote — then idle again.

Encoding (focus) is the only required open-ended phase. Prime and recall have ends. Break is **not** a protocol phase in the old sense; it is the earned interlude between focus and recall.

**Skip** is always available on timed beats (prime, break, recall). Skip during focus is the same as Stop (you have chosen to end focus).

---

## 5. The window (locked)

The Mac **window is the product**.

- **One surface.** Same compact frame. The insides change. No Home, no tabs, no setup-then-another-app.
- **Size.** Compact, corner-of-the-desk. Not a document window, not full screen.
- **Always on top.** Off by default. One control to pin over your work.
- **Look.** Not designed yet. Do not invent a new brand in the first implementation pass unless asked. The old iPhone app was black + cyan; that is a *reference*, not a mandate.

### States

| State | On screen | Actions |
|---|---|---|
| **Idle** | Clock at 00:00. Last intention already filled. **Start**. A small **today** total (focus time today only). | Edit the line or Start. |
| **Prime (2:00)** | Same intention line. Stilling. Countdown + **determinate** ring. | Sit. Skip. |
| **Focus** | **Big count-up clock** (the hero). Under it: **thin strip + “Xm earned”** growing as `elapsed / ratio`. A **+** that opens the capture line. Stop. | Work. Park a thought. Stop. |
| **Break** | Countdown + determinate ring. Copy that this rest was earned. | Sit. Skip. |
| **Recall (5:00)** | The question: **What did you just do?** Optional text. Countdown + ring. | Write, sit, or skip. |
| **Close beat** | Focus duration, break duration, recall text if any. No score, no share, no phase laundry list. | Then idle. |

### Focus visual (important)

Count-up has no finish line. A 0–100% “progress” ring during focus is a **lie** (that is Pomodoro). Do not add one.

- Timed phases (prime, break, recall) → real ring/bar that has an end.
- Focus → big clock + **earned-break strip** (information: rest you are accruing).

This is the “on steroids” visual that is still honest.

### Capture

Not an always-visible field. A small **+** on the focus state opens one line. Enter parks it and clears. No sheet, no categories in v1 (distraction vs idea can be inferred later; don’t ask now).

### Pause

**No Pause button** while working. You are in, or you Stop (and earn the break).

Pause exists only as **recovery**:

- Quit the app, or the Mac sleeps → on return the session is **paused**.
- On return: same phase, clock frozen, one **Continue**. Bringing the window forward does not resume. Continue resumes from the frozen time.

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
| **CLI / JSON API** | For agents and scripts | Same verbs, same store as the window |
| **iPhone** | Signed slice ([`iphone.md`](iphone.md)) | Same loop, local store; iCloud later |
| **Widgets** | Out | After the iPhone app exists |

### CLI / agents (intent, not a command lifestyle)

Humans do not run a session by typing `start` → `status` → `skip` → `stop`. That was a mistake in an early sketch.

Agents and scripts **may** fire verbs against a session the window (or a living TUI) is already showing:

- start with a label  
- stop focus  
- skip current timed beat  
- capture a line  
- status as JSON  
- read/set config (ratio, durations)  
- later: explain why the ratio moved  

The API talks to the **same** live session as the window. Two clocks is a bug.

---

## 7. Learning (locked, narrow)

After each completed session, record focus duration.

- Last **three** sessions all **≥ 45 min** → next `ratio` decreases by **0.25** (longer break). Floor **3**.
- Last **three** all **≤ 20 min** → next `ratio` increases by **0.25** (shorter break). Ceiling **8**.
- Otherwise ratio stays.

Prime stays 2:00. Recall stays 5:00. Learning does **not** turn recall or prime on/off in v1.

The profile should be inspectable (a file or `status` field) so an agent can see the current ratio and, later, a one-line reason. The idle window does not need a lecture about it.

---

## 8. Numbers and names

| Thing | Value | Notes |
|---|---|---|
| Prime | 120 s | Skip allowed |
| Focus | open | Count up |
| Break | `focus / ratio` | Ratio starts at 5 |
| Recall | 300 s | Skip allowed |
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
- Prime 2 min, recall 5 min
- Park a thought mid-session
- Dark compact session energy (reference only)
- Tagline and name

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

`/Users/facspro/dev/flowmo` was an **early engine sketch** (Swift package: `FlowmoCore`, a verb-style CLI, a check binary). It was started during brainstorming and is **not** the product.

Treat it as:

- Proof that break math and a file store can be headless
- **Not** the UX
- **Not** a mandate to keep the CLI as the daily interface

A future implementation should implement **this brief**, not grow that CLI into the app. Reuse the reducer/store ideas if they still fit; throw away anything that smells like command tennis.

macOS on this machine is case-insensitive: `~/flowmo` and `~/Flowmo` are the **same path**. New work must stay under `~/dev/flowmo` (or another name that is not `Flowmo`).

Core proofs use `swift run flowmo check` (`import XCTest` / `import Testing` may fail without full Xcode). The Dock `.app` is a thin Xcode host of the same window (`Apps/Flowmo.xcodeproj`, bundle `app.flowmo.mac`); `swift run` remains the SwiftPM launcher.

---

## 11. Technical direction (enough to start, not a spec lock)

When implementation begins, the shape that matches this brief:

1. **One session store** (timestamps + state). Elapsed time is `now - startedAt`. Break remaining is `endsAt - now`. Any UI is a view.
2. **One live session**, file lock if CLI/agents share the store.
3. **Mac window first** (SwiftUI). Compact. States above. Then optional living terminal. Then agents. Then iPhone.
4. Do **not** start by opening a new Xcode clone of `~/Flowmo`.
5. Persistence: a small local store (JSON or SQLite under `~/.flowmo/`). SwiftData is not required.
6. Notifications and sound are adapters around phase transitions, not the engine.

Suggested first vertical slice when someone is told to build: **idle → type once → prime → focus (clock + earned strip + + capture) → stop → break ring → recall → close beat → idle**, with hide-window-keeps-running and quit-returns-paused. No menu bar, no history list, no themes.

---

## 12. Later (explicitly not v1)

- Visual identity / themes (beyond the signed compact pass)
- Menu bar as the product (glance is in [`menu-bar.md`](menu-bar.md))
- iPhone client (signed: [`iphone-tasks.md`](iphone-tasks.md); local, no iCloud)
- Widgets, Watch, iCloud (after iPhone)
- Flashcards, SM-2, consolidation, reflection
- History browser
- Learning anything other than break ratio
- Monetization, licensing, marketing (out of scope for this brief)

---

## 13. Decision log

Made with the owner in conversation, 2026-08-17 → 2026-08-18.

| Decision | Choice |
|---|---|
| Still a scientific Flowmodoro, not a generic timer | Yes |
| Start | Setup then prime; do not drop the fundamentals |
| Type intention | Once, at idle. Prime only displays it. |
| After focus | Earned break, then short recall |
| Capture in v1 | Yes, one line, via **+** |
| First place it lives | Mac, **real window** as the main thing |
| Window structure | One frame, states change |
| Prime | Intention + stilling (2:00) |
| Recall | Question + optional lines (5:00) |
| Focus visual | Big clock + thin earned-break strip and “Xm earned” |
| Timed-phase visual | Determinate ring/bar |
| Fake 0–100% focus bar | No |
| Menu bar | Glance only ([`menu-bar.md`](menu-bar.md)). Window stays the product. |
| Terminal | `flowmo live` is a ticking view. Verbs stay a side door. |
| Learning in v1 | Quiet; **ratio only** |
| Window size | Compact; optional float on top |
| Pin default | Off |
| Look | Compact pass in [`visual.md`](visual.md) (black + cyan reference). Not a theme pack. |
| Idle | Last intention + Start + today total |
| Sound | Soft cues **on** by default |
| Background phase end | Sound + system notification |
| Close / hide window | Session keeps running |
| Quit / sleep | Restore **paused** |
| Resume after quit / sleep | One **Continue**. Window appearing does not resume. |
| Pause button | No |
| After recall | Quiet close beat; **click to dismiss** (Skip = dismiss). Then idle |
| History UI | Today line only |
| Window delivery | SwiftPM launcher (`swift run`) plus thin Xcode wrap of the same window (`Apps/Flowmo.xcodeproj`, bundle `app.flowmo.mac`) |
| Session store | JSON at `~/.flowmo/world.json` with a file lock |

---

## 14. Handoff checklist

Someone picking this up cold should be able to:

1. Read this file and describe the loop and the window without looking at chat.
2. Ignore `~/Flowmo` except for the formula and the old timer/break screens as visual reference.
3. Ignore the sketch CLI as UX.
4. Implement the compact Mac window against a timestamped session store.
5. Keep CLI/JSON as a side door to that same store.
6. Not add Home, scores, flashcards, or a 25-minute countdown unless the owner reopens those decisions.

When a formal visual/engineering design is wanted, start from **this** document, not from `FLOWMO_VISION.md` or `APP_STORE_MVP_LAUNCH_PLAN.md` in the old repo.
