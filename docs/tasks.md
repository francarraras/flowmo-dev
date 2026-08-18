# Flowmo v1 — tasks

Rewritten from the signed engineering plan [`design.md`](design.md).  
Done means [`acceptance.md`](acceptance.md) holds.

Signed off by the captain on 2026-08-18. Implementation of this list is allowed.

Do not start a second store. Do not add a brand, menu bar, living TUI, Xcode app target, or pause-during-focus.

---

1. **Evolve Core to the signed state machine**  
   Idle (`live == nil`) → prime → focus → break → recall → closeBeat → idle. Names in the window: Focus, not “encoding”. Intention once at idle (`lastIntention`). Skip on prime/break/recall/closeBeat; Skip during focus = stop. Break = `focus / ratio`. Close beat stays until click/Skip; no auto-idle. Recall optional text on the snapshot. Today total from completed focus at local midnight. Ratio from last three focus durations (floor 3, ceiling 8, step 0.25). Clock from timestamps.

2. **Recovery pause is any phase**  
   Quit/sleep → freeze **current** phase. Continue resumes **that** phase. No Pause control on the window. Remove CLI `pause`/`resume` as flow verbs; recovery continue may be an engine event the window calls.

3. **JSON store remains the only session**  
   `~/.flowmo/world.json`, atomic write, `world.lock`. Additive fields as in the design. Window and CLI share this file only.

4. **FlowmoWindow**  
   Compact SwiftUI frame for every phase plus paused+Continue. Focus: count-up, earned strip, **+** capture. Timed phases: determinate ring. Close beat: summary until click. Idle: last intention, Start, today total. Pin default off. Plain chrome. No fake focus %, no Home/tabs.

5. **Thin SwiftPM launcher**  
   `swift run` hosts the window. Quit/sleep → Core recovery pause. Do not put the product in `main.swift`. Later Xcode wraps the same window.

6. **Window follows timestamps and the file**  
   Ticks from Core numbers. Reloads when `world.json` changes. Hide/close keeps the session running. Appearing after pause does not Continue.

7. **Sound and notification adapters**  
   Soft cue on phase change (default on). Background: cue + system notification; activating it brings the window forward.

8. **CLI side door**  
   `status --json` and verbs against Core. Snapshot, not a ticking TUI. Not how humans run a session.

9. **Prove it**  
   Core checks for the loop, skip=stop, freeze any phase + same-phase Continue, close beat does not auto-idle, break math, last-3 ratio, today total, one live session. Manual: `swift run` through the loop, hide/reopen, quit/Continue, click dismiss, CLI status while the window ticks. If XCTest cannot import, use the package check that compiles. Do not wait on full Xcode.

---

Implementation starts only after this rewritten list is signed. Anything not listed is a later slice.
