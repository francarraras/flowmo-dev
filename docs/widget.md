# Flowmo — iPhone widget

The Home Screen widget is a glance over the phone's Core clock. The iPhone app
remains the phone product. Mac glance behavior stays in
[`menu-bar.md`](menu-bar.md). The implementation is a private-beta candidate;
the simulator build and runtime checks belong to the release verification gate.

---

## Why this slice

iPhone has no menu bar. After the local phone app exists, a widget is the analogue of the Mac status item: time visible when the app is not open. It is not a session.

## Outcome

A small Home Screen widget that shows the **same** `Format.glance` string the Mac menu bar would: remaining on prime/break/recall, count-up on Focus, frozen with a leading `·` while recovery-paused, `Flowmo` when idle.

Tap opens the existing iPhone app. Tap does **not** Continue.

Copy does not claim productivity, well-being, or flow.

## In

- One WidgetKit extension on `Apps/FlowmoPhone.xcodeproj`. Bundle family under `app.flowmo.phone`.
- Same `world.json` the phone already writes, via an **App Group** so the extension can read it. Core `Store(root:)` and Engine timestamps. No second clock, no second engine.
- The phone reloads the timeline after store writes. Timeline entries cover timed phase boundaries. SwiftUI timer text renders live count-up/countdown from Core timestamps; there is no 1-second app timer.
- Small / medium is enough. Field and clock ink follow `Atmosphere.of(phase)`. **Focus has no progress ring.** Gold rest is not on the glance.
- Same recovery rule as the app: a paused session shows the frozen clock and `·`. Opening from the widget still does not Continue.

## Out

Start, Skip, Stop, +, mute, Continue from the widget. Live Activities, Watch, Lock Screen complications (unless they fall out of the same glance for free — do not chase them). Mac widgets. iCloud. History. Theme packs. Home, tabs, scores. `~/Flowmo`.

## Phone vs widget (honest)

The widget reads a session snapshot, then SwiftUI advances the visible clock from its timestamps. Phase and pause changes still require a timeline reload; the clock itself must not freeze between reloads.

## Checkable lines

WHEN the widget is idle
THE SYSTEM SHALL show `Flowmo` (same as the Mac glance).

WHEN Focus is live (unpaused)
THE SYSTEM SHALL show a live count-up from Core timestamps and SHALL NOT show a 0–100% ring.

WHEN a timed phase is live
THE SYSTEM SHALL show a live countdown from Core timestamps.

WHEN the session is recovery-paused
THE SYSTEM SHALL show the frozen glance with a leading `·`.

WHEN the user taps the widget
THE SYSTEM SHALL open the iPhone app and SHALL NOT Continue.

WHEN the phone app writes `world.json`
THE SYSTEM SHALL reload the widget timeline.

WHEN the App Group cannot share the store or the store cannot be validated
THE SYSTEM SHALL show `Unavailable`, retry on a later timeline, and SHALL NOT
crash, write, or invent a second JSON file the app never writes.
