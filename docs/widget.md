# Flowmo — iPhone widget

The Home Screen widget is a glance over the phone's Core clock. The iPhone app remains the phone product. Mac glance behavior stays in [`menu-bar.md`](menu-bar.md). Shipped and simulator-proved on 2026-08-21.

---

## Why this slice

iPhone has no menu bar. After the local phone app exists, a widget is the analogue of the Mac status item: time visible when the app is not open. It is not a session.

## Outcome

A small Home Screen widget that shows the **same** `Format.glance` string the Mac menu bar would: remaining on prime/break/recall, count-up on Focus, frozen with a leading `·` while recovery-paused, `Flowmo` when idle.

Tap opens the existing iPhone app. Tap does **not** Continue.

Copy does not claim productivity, well-being, or flow.

## In

- One WidgetKit extension on `Apps/FlowmoPhone.xcodeproj`. Bundle family under `app.flowmo.phone`.
- Same `world.json` the phone already writes, via an **App Group** so the extension can read it. Core `Store(root:)` + `Format.glance`. No second clock, no second engine.
- Timeline: reload when the app writes the store; plus a coarse WidgetKit schedule so a live Focus/prime clock is not frozen for hours. Honest lag between reloads is allowed. Do not fake a 1-second UI timer as source of truth.
- Small / medium is enough. Black field, white clock, cyan only if a timed ring is shown; **Focus has no progress ring**.
- Same recovery rule as the app: a paused session shows the frozen clock and `·`. Opening from the widget still does not Continue.

## Out

Start, Skip, Stop, +, mute, Continue from the widget. Live Activities, Watch, Lock Screen complications (unless they fall out of the same glance for free — do not chase them). Mac widgets. iCloud. History. Theme packs. Home, tabs, scores. `~/Flowmo`.

## Phone vs widget (honest)

The app process can suspend. The widget process is a snapshot. Clocks stay honest because they are timestamps at **reload** time. Between reloads the face may be stale. That is a glance, not a live TUI.

## Checkable lines

WHEN the widget is idle
THE SYSTEM SHALL show `Flowmo` (same as the Mac glance).

WHEN Focus is live (unpaused)
THE SYSTEM SHALL show a count-up from Core timestamps at last reload and SHALL NOT show a 0–100% ring.

WHEN a timed phase is live
THE SYSTEM SHALL show remaining from Core at last reload.

WHEN the session is recovery-paused
THE SYSTEM SHALL show the frozen glance with a leading `·`.

WHEN the user taps the widget
THE SYSTEM SHALL open the iPhone app and SHALL NOT Continue.

WHEN the phone app writes `world.json`
THE SYSTEM SHALL reload the widget timeline.

WHEN an App Group cannot share the store
THE SYSTEM SHALL stop this slice (spike fails). Do not invent a second JSON file the app never writes.
