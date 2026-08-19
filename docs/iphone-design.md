# Flowmo — iPhone (design)

Plan for [`iphone.md`](iphone.md). Tasks: [`iphone-tasks.md`](iphone-tasks.md). Signed by the captain on 2026-08-19.

Do not change signed v1 [`design.md`](design.md) / [`tasks.md`](tasks.md). Do not start from `~/Flowmo`.

---

## 1. Modules

| Module | Owns | Must not own |
|---|---|---|
| **FlowmoCore** | Same Engine, JSON, lock, clocks. Package must also build for iOS. | UI, notifications. |
| **FlowmoPhone** (new) | SwiftUI loop, mute, Continue, +, schedule/cancel notifications, `Store(root: app container)`. | Second Engine, AppKit, Guard. |
| **Apps/FlowmoPhone** | Thin Xcode iOS host. Bundle `app.flowmo.phone`. | Business rules. |

Mac `FlowmoWindow` stays Mac. Copy layout intent from [`visual.md`](visual.md), not NSWindow types.

`Store.default` is `~/.flowmo`. The phone **must** pass `Store(root:)` under Application Support. Same `world.json` + `world.lock`.

## 2. Lifecycle (spike this first)

| Mac | iPhone |
|---|---|
| Hide / close | Background: **do not pause**. Process will suspend; timestamps still tell the truth. |
| Quit / sleep | Cold start with unpaused `live`: persist `pauseForRecovery` **before** UI. Appearing does not Continue. |
| Process still running | Phone lock with app in memory: still not paused. |

On every launch: load → if `live` exists and is not paused → `pauseForRecovery` → then show Continue.

If the spike cannot tell “backgrounded” from “killed”: pause only on process start (the rule above). Document it. Do not invent a Pause button.

## 3. Attention

Reuse `AttentionCue.shouldPlay`. Foreground: play a short system sound if `cuesEnabled`.

Background / suspended: you cannot `sync` on a timer. When Core enters prime, break, or recall, **schedule** a `UNNotification` for `now + remaining`. Cancel that request on Skip, Stop, Continue-into-another-phase, mute does **not** cancel the banner (mute is sound only). Tap: open; do not Continue.

Focus has no end time. No scheduled “stop focusing” banner.

## 4. UI

One frame. Same states as Mac. Mute in chrome. No pin. No Guard line. Content clears Dynamic Island and home indicator. Compact, not a document list.

## 5. Package

Today `Package.swift` is `.macOS(.v13)` only. Spike may add iOS to **FlowmoCore** (and only Core) so the phone target can link it. Do not make `FlowmoWindow` an iOS target.

## 6. Proof

- `swift run flowmo check` still green on Mac.
- Simulator: full loop; Skip during Focus = Stop; background and return still moving or already advanced; kill → Continue; notification tap does not Continue; mute in JSON.
- Physical device is extra, not required for done.
