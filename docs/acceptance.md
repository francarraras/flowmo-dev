# Flowmo v1 — checkable lines

Clarify artifact. Product story stays in [`PROJECT.md`](PROJECT.md). House rules stay in [`../AGENTS.md`](../AGENTS.md).

These lines are what a worker must satisfy. If a behavior is not here and not in those two files, it is out of v1.

Signed off by the captain on 2026-08-18.

---

## Loop

WHEN the window is idle  
THE SYSTEM SHALL show a clock at 00:00, the last intention already filled, a Start control, and today’s completed-focus total (local midnight).

WHEN the user edits the idle line and starts  
THE SYSTEM SHALL use that line as the session intention and SHALL NOT ask for it again during Prime.

WHEN a session starts  
THE SYSTEM SHALL enter Prime for 120 seconds, show the intention, and show a determinate countdown ring.

WHEN the user skips Prime, or Prime reaches 0  
THE SYSTEM SHALL enter Focus.

WHEN the session is in Focus  
THE SYSTEM SHALL count **up** from a timestamp (not from a 1-second UI timer as source of truth), show a big elapsed clock, show a thin earned-break strip and “Xm earned” as `elapsed / ratio`, and offer a **+** that opens one capture line.

WHEN the user submits a capture line during Focus  
THE SYSTEM SHALL park that line and clear the field. No sheet, no categories.

WHEN Focus is showing  
THE SYSTEM SHALL NOT show a 0–100% progress ring, a Pause control, Home, tabs, or a menu bar.

WHEN the user stops Focus, or skips during Focus  
THE SYSTEM SHALL end Focus and start Break of length `focus / ratio` (default ratio 5), with a determinate ring and copy that the rest was earned.

WHEN the user skips Break, or Break reaches 0  
THE SYSTEM SHALL enter Recall for 300 seconds, show “What did you just do?”, allow optional text, and show a determinate ring.

WHEN the user skips Recall, or Recall reaches 0  
THE SYSTEM SHALL show one quiet close beat (focus duration, break duration, recall text if any) until the user clicks to dismiss (Skip counts as dismiss), then return to Idle. No score, no share, no phase laundry list. No auto-advance timer.

## Window and recovery

WHEN the user hides or closes the window during a live session  
THE SYSTEM SHALL keep that session running. Reopening shows the same phase, still moving.

WHEN the user quits the app, or the Mac sleeps, during a live session  
THE SYSTEM SHALL restore that session **paused**: same phase, clock frozen, one **Continue** control.

WHEN the paused window appears or comes forward  
THE SYSTEM SHALL NOT resume by itself.

WHEN the user hits Continue on a paused session  
THE SYSTEM SHALL resume the same phase from the frozen time.

WHEN any live session exists  
THE SYSTEM SHALL NOT start a second one.

## Attention

WHEN a phase change occurs (Prime ended, Focus stopped, Break ended, Recall ended)  
THE SYSTEM SHALL play a soft cue (on by default).

WHEN that phase change happens while the window is in the background  
THE SYSTEM SHALL also post a system notification. Activating the notification SHALL bring the window forward.

## Learning (quiet)

WHEN a session completes Focus  
THE SYSTEM SHALL record that focus duration.

WHEN the last three completed focus durations are all ≥ 45 minutes  
THE SYSTEM SHALL decrease the next ratio by 0.25, not below 3.

WHEN the last three are all ≤ 20 minutes  
THE SYSTEM SHALL increase the next ratio by 0.25, not above 8.

WHEN neither streak holds  
THE SYSTEM SHALL leave the ratio unchanged.

Prime stays 120 s. Recall stays 300 s. Learning SHALL NOT toggle Prime or Recall in v1.

## Out of this file

Look/brand, storage format, exact SwiftUI chrome, and pin-on-top control details are Plan, not Clarify.
