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
| iCloud | Private CloudKit sync with the Mac app. |
| Watch | Later. |

## Outcome

One iPhone app that runs:

idle → type once → prime (2:00) → focus (count up, you stop) → earned break → reflection (3:00) → close beat → idle.

Kill the app → paused with **Continue** and **Restart**. Opening the app does not Continue by itself.

Copy does not claim productivity, well-being, or flow.

## In

- New iOS app in **this** repo. Rules and JSON from **FlowmoCore**. New SwiftUI frame. **Not** AppKit `FlowmoWindow`. **Not** `~/Flowmo`.
- Same `world.json` schema. File lives in the phone/widget App Group container (not `~/.flowmo`). Same bounded validation, lock, and atomic write. The phone app synchronizes the loop through the user's private CloudKit database; the widget only reads the App Group copy.
- Same controls as Mac: Start, Skip, Stop, +, Continue, Restart, mute, and Idle-only Data controls. **No pin.** **No Focus Guard.** **No menu bar.** **No `flowmo live`.**
- Same look rules: black field, cyan on Start and timed rings, clock-in-ring on prime/break/recall, Focus is a count-up plus earned strip. No focus progress ring. No Home. No tabs.
- Cues on by default (`cuesEnabled`). Mute silences sound. Phase end while you are not looking: a local notification. Tap opens the app; it does not Continue.

## Out

Home, tabs, setup, scores, streaks, flashcards, SM-2, history dashboard, Watch, Live Activities, a second engine, Pause during Focus, App Store launch work.

## Phone vs Mac (honest)

On Mac, hide/close leaves Flowmo running. On iPhone, background **suspends** the process. Clocks stay honest because they are timestamps, not a ticking timer. Timed phases that should have ended while you were away catch up when Core `sync`s on the next launch or foreground.

Notifications for “prime ended / break ended / recall ended” while away are **scheduled when that timed phase starts**, then cancelled if you Skip or Stop first. The UI/Core timer does not run continuously in the background. iOS may grant
`CKSyncEngine` bounded background execution for remote database notifications;
persisted timestamps remain the clock authority when the interface returns.

## Checkable lines

WHEN the app is idle
THE SYSTEM SHALL show 00:00, last intention, Start, today’s focus total, History, and Data.

WHEN the user opens History from Idle
THE SYSTEM SHALL show completed sessions newest-first. Each card shows intention, Focus duration, and local date. Tapping a card SHALL expand that session in place with Focused, Rested, parked lines, and reflection when present. Back SHALL return to Idle.

WHEN the user starts
THE SYSTEM SHALL enter Prime for 120s with that intention and SHALL NOT ask for it again during Prime.

WHEN Focus is showing
THE SYSTEM SHALL count up from timestamps, show earned rest, offer +, and SHALL NOT show Pause, a 0–100% focus ring, Home, or tabs.

WHEN the user backgrounds the app during a live session
THE SYSTEM SHALL not pause. On return the same phase is still moving (or already advanced if a timed beat ran out).

WHEN a session arrives from the Mac through private CloudKit
THE SYSTEM SHALL display the same timestamped session and SHALL NOT pause it as
an iPhone process-recovery event.

WHEN both devices start or ambiguously change a session while offline
THE SYSTEM SHALL block loop controls and require **Keep this iPhone** or **Use
iCloud version**. It SHALL NOT silently merge two live sessions.

WHEN CloudKit is signed out or unavailable
THE SYSTEM SHALL remain usable against its local store and queue later sync.
Changing iCloud accounts SHALL require an explicit data choice before upload.
A missing iCloud account or entitlement SHALL NOT occupy the session interface;
structural or unknown sync failures, pending deletion, and account-choice
problems remain visible.

WHEN the process is killed during a live session
THE SYSTEM SHALL restore paused with Continue and Restart. Appearing SHALL NOT resume. Restart SHALL drop the frozen session and start Prime with the same intention.

WHEN a timed phase (prime, break, recall) will end while the app is not foreground
THE SYSTEM SHALL schedule a local notification for that end. Skip, Stop, or an earlier phase change SHALL cancel it. Activating the notification SHALL open the app and SHALL NOT Continue.

WHEN `world.json` is a Mac-shaped document
THE SYSTEM SHALL load it. Guard fields have no iPhone UI.

WHEN the App Group container is unavailable
THE SYSTEM SHALL show a calm unavailable state with Retry and SHALL NOT crash or
fall back to a different store.

WHEN the shared store is invalid
THE SYSTEM SHALL offer Retry, redacted diagnostics, or Preserve & Reset. The
original bytes SHALL be preserved before reset.

WHEN the user opens Data from Idle
THE SYSTEM SHALL offer full export, redacted diagnostic export, and explicitly
confirmed Delete All. Delete All SHALL remove Flowmo-owned recovery copies and
reload the widget timeline. It SHALL remove local private sync replicas
immediately and SHALL report incomplete deletion until queued CloudKit deletion
is confirmed.
