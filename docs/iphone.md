# Flowmo — iPhone

The iPhone app runs the same Core loop in its own native frame. The Mac window remains the main Mac product. Product rules stay in [`PROJECT.md`](PROJECT.md).

---

## Why iPhone first

| Later item | This slice |
|---|---|
| **iPhone** | Yes. Same loop, one compact frame. |
| Widgets | After the app exists. A widget is a glance, not a session. |
| History | Plain local completed-session list from Idle. |
| Theme packs | Black + cyan from [`visual.md`](visual.md). Not a pack. |
| iCloud / Watch | After a working phone. This slice is **local**. |

## Outcome

One iPhone app that runs:

idle → type once → prime (2:00) → focus (count up, you stop) → earned break → recall (5:00) → close beat → idle.

Kill the app → paused + one **Continue**. Opening the app does not Continue by itself.

Copy does not claim productivity, well-being, or flow.

## In

- New iOS app in **this** repo. Rules and JSON from **FlowmoCore**. New SwiftUI frame. **Not** AppKit `FlowmoWindow`. **Not** `~/Flowmo`.
- Same `world.json` schema. File lives in the app container (not `~/.flowmo`). Same lock + atomic write.
- Same controls as Mac: Start, Skip, Stop, +, Continue, mute. **No pin.** **No Focus Guard.** **No menu bar.** **No `flowmo live`.**
- Same look rules: black field, cyan on Start and timed rings, clock-in-ring on prime/break/recall, Focus is a count-up plus earned strip. No focus progress ring. No Home. No tabs.
- Cues on by default (`cuesEnabled`). Mute silences sound. Phase end while you are not looking: a local notification. Tap opens the app; it does not Continue.

## Out

Home, tabs, setup, scores, streaks, flashcards, SM-2, history dashboard, widgets, Watch, Live Activities, iCloud, a second engine, Pause during Focus, App Store launch work.

Mac and iPhone are **two local files** until iCloud. They do not share a live session.

## Phone vs Mac (honest)

On Mac, hide/close leaves Flowmo running. On iPhone, background **suspends** the process. Clocks stay honest because they are timestamps, not a ticking timer. Timed phases that should have ended while you were away catch up when Core `sync`s on the next launch or foreground.

Notifications for “prime ended / break ended / recall ended” while away are **scheduled when that timed phase starts**, then cancelled if you Skip or Stop first. Do not wait for a live `sync` in the background — it will not run.

## Checkable lines

WHEN the app is idle
THE SYSTEM SHALL show 00:00, last intention, Start, today’s focus total, and History.

WHEN the user opens History from Idle
THE SYSTEM SHALL show completed sessions newest-first with intention, Focus duration, and local date. Back SHALL return to Idle.

WHEN the user starts
THE SYSTEM SHALL enter Prime for 120s with that intention and SHALL NOT ask for it again during Prime.

WHEN Focus is showing
THE SYSTEM SHALL count up from timestamps, show earned rest, offer +, and SHALL NOT show Pause, a 0–100% focus ring, Home, or tabs.

WHEN the user backgrounds the app during a live session
THE SYSTEM SHALL not pause. On return the same phase is still moving (or already advanced if a timed beat ran out).

WHEN the process is killed during a live session
THE SYSTEM SHALL restore paused with one Continue. Appearing SHALL NOT resume.

WHEN a timed phase (prime, break, recall) will end while the app is not foreground
THE SYSTEM SHALL schedule a local notification for that end. Skip, Stop, or an earlier phase change SHALL cancel it. Activating the notification SHALL open the app and SHALL NOT Continue.

WHEN `world.json` is a Mac-shaped document
THE SYSTEM SHALL load it. Guard fields have no iPhone UI.
