# Flowmo — Focus Guard (design)

Plan artifact for the Focus Guard slice. Product: [`focus-guard.md`](focus-guard.md). Tasks: [`focus-guard-tasks.md`](focus-guard-tasks.md). Signed by the captain on 2026-08-19.

Do not mutate signed v1 [`design.md`](design.md) / [`tasks.md`](tasks.md).

---

## 1. Feasibility first

Disposable spike (throwaway, isolated `FLOWMO_HOME` if it touches the store at all). Prove:

1. `NSWorkspace.didActivateApplicationNotification` names the foreground app.
2. `NSRunningApplication.hide()` is acceptable on a native app, an Electron app, a multi-window app, and a full-screen app.
3. Open-once can reactivate without an observer loop.
4. Guarding continues with Flowmo’s window hidden.
5. `swift run` and the ad-hoc Dock app both work, or document which does not.
6. No Accessibility permission or extra entitlement.

If the spike fails: stop. Do not escalate to Accessibility, kill, a helper, or a system extension.

## 2. Core

Add to `Config` (additive Codable, default off):

```swift
struct FocusGuardConfiguration: Codable, Equatable, Sendable {
    var enabled: Bool
    var bundleIdentifiers: [String]
}
```

Normalize IDs: trim, drop empties/duplicates, drop Flowmo and forbidden system IDs, sort. AppKit types stay out of Core.

One Engine event for config mutation. `Store.update` remains the only serialized write. Failed persist must not turn the adapter on.

## 3. Window adapter

`FlowmoWindow` only. Protocol + fake for checks.

Desired state:

```swift
enum FocusGuardDemand: Equatable {
    case inactive
    case active(sessionID: UUID, bundleIdentifiers: Set<String>)
}
```

Reconcile from World after: launch, successful local persist, timed transition persist, external reload, pause, Continue, config change. Persist first.

Open-once: allow by running-process id until deactivation.

## 4. UI

Same compact frame.

- Idle: `Guard: Off` / `Guard: N apps` → expand in-place: toggle, add (file picker), remove.
- Focus: secondary status only; intercept copy under the clock, not instead of it.
- Degraded: short truthful line. Start still works.

## 5. Proof

Checks: decode, normalize, demand matrix (phase × paused × enabled × list), idle-only mutate, failed write does not activate, fake adapter idempotency, open-once.

Manual: native / Electron / multi-window / full-screen; hide window; Stop / Skip / quit-Continue; CLI phase change while the window process lives.
