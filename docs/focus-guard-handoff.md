# Flowmo Focus Guard — future handoff

Status: researched product/engineering plan; **not part of signed v1 and not implementation authorization**  
Decision date: 2026-08-19  
Chosen scope: Mac apps only, best-effort soft guard

Before implementation, reconcile this document with [`../AGENTS.md`](../AGENTS.md) and [`PROJECT.md`](PROJECT.md), then create or approve a dedicated acceptance/design/tasks slice. Do not silently add this feature to the signed v1 task list.

## Outcome

Add an optional **Focus Guard** that introduces friction when the user opens selected Mac apps during an unpaused Flowmo Focus.

This is not a security boundary or an unbreakable blocker. The user can choose **Open once**, quit Flowmo, or bypass the mechanism through macOS. Product copy must describe it as a guard or friction, not guaranteed blocking.

The reference screenshot's count-up concept is already Flowmo's core behavior. Do not import its progress ring, awards, streaks, block history, or timer rationale.

## Product boundary

### In scope

- Disabled by default.
- One remembered set of selected `.app` bundles.
- Configuration from Idle in the existing compact window.
- Automatic guarding during active, unpaused Focus.
- Neutral interception copy with **Stay focused** and **Open once**.
- Subtle factual status during Focus, such as `Guarding 3 apps`.
- The same behavior from both `swift run` and the Dock app, subject to the feasibility spike.
- Configuration stored as stable bundle identifiers in the existing Flowmo JSON store.

### Out of scope

- Websites or browser extensions.
- `FamilyControls`, `ManagedSettings`, Screen Time shields, or Device Activity.
- Accessibility control, process termination, privileged helpers, launch agents, Network Extensions, or system extensions.
- Hard/irreversible blocking.
- Schedules, multiple named lists, per-session setup, categories, or commitment-strength modes.
- Block counts, attempt logs, analytics, scores, awards, streaks, history, or time-saved estimates.
- Enforcement while no Flowmo window process is running.
- Claims that the feature improves productivity, well-being, flow, or focus duration.

## User behavior

### Configure

While Idle, the compact window exposes one control:

- `Guard: Off`
- `Guard: N apps`

Opening it temporarily expands or replaces content within the same frame; it does not introduce Home, tabs, a setup wizard, or a second window. The user can:

1. Enable or disable the guard.
2. Add one or more application bundles with a native file picker.
3. Remove selected applications.

Persist bundle identifiers, not display names or file paths. Resolve names and icons at presentation time. Exclude Flowmo itself and critical macOS processes from selection.

### Enter Focus

Prime is unchanged. After a Prime → Focus transition has been successfully persisted, guarding begins when:

```text
config.enabled
&& !config.bundleIdentifiers.isEmpty
&& live.phase == focus
&& !live.isPaused
```

The existing count-up clock remains the hero. Guard status is secondary and must not become a progress visualization.

### Intercept an app

When `NSWorkspace` reports that a selected app became active:

1. Ask `NSRunningApplication` to hide it.
2. Bring Flowmo forward.
3. Show `"<App> is guarded during this Focus."`
4. Offer:
   - **Stay focused** — dismiss the message.
   - **Open once** — allow and activate that process until it next loses activation.

The next activation after an Open-once allowance is consumed must be guarded again. Do not terminate, suspend, or modify the selected app.

### Lifecycle

| Flowmo state/action | Guard |
|---|---|
| Idle, Prime, Break, Recall, Close beat | Inactive |
| Active unpaused Focus | Active |
| Recovery-paused Focus | Inactive |
| Continue a paused Focus | Active again |
| Hide or close Flowmo's window | Remains active |
| Stop, Skip from Focus, or Cancel | Inactive |
| Quit, sleep, power-off, SIGINT, or SIGTERM | Inactive; session still follows existing recovery-pause behavior |
| Adapter error or unsupported app behavior | Fail open and report truthful degraded status |
| Flowmo process absent or crashed | Inactive |

Because this design only observes activation and calls `hide()`, a crash cannot strand an OS-level restriction.

## Feasibility gate

Before changing product behavior, build a disposable spike that proves:

1. `NSWorkspace.didActivateApplicationNotification` reliably identifies the foreground app.
2. `NSRunningApplication.hide()` produces acceptable behavior for representative native, Electron, multi-window, and full-screen apps.
3. An allowed app can be reactivated once without an observer loop.
4. Guarding continues when Flowmo's window is hidden.
5. Behavior is acceptable from both `swift run` and the current ad-hoc-signed Dock app.
6. No Accessibility permission or special entitlement is required.

If this spike fails, stop and reopen the product decision. Do not escalate silently to Accessibility, app termination, a helper daemon, or a system extension.

## Technical design

### Core model

Add a platform-neutral configuration, conceptually:

```swift
struct FocusGuardConfiguration: Codable, Equatable, Sendable {
    var enabled: Bool
    var bundleIdentifiers: [String]
}
```

Add it to `Config`, defaulting to disabled and an empty list. `Config` currently uses synthesized `Codable`; introduce backward-compatible decoding so existing `world.json` files without the new field still load.

Normalize identifiers by trimming, removing empties and duplicates, excluding forbidden identifiers, and sorting before persistence. AppKit types, running-process identifiers, icons, and file paths must not enter `FlowmoCore`.

Use an Engine event for configuration mutation so `Store.update` remains the single serialized mutation path. Configuration UI is Idle-only. A script or agent may inspect the same persisted values, but expanding the human CLI is not part of this slice.

### Window adapter

Add a macOS-only adapter under `FlowmoWindow`, behind an injectable protocol. Its responsibilities are:

- Start and stop observing workspace activation.
- Reconcile idempotently from desired state rather than transition guesses.
- Match activated apps by bundle identifier.
- Hide selected applications.
- Track a one-use allowance by running-process identifier until deactivation.
- Publish ephemeral runtime status and the latest interception.
- Bring the existing Flowmo window forward through an injected callback.

Suggested desired-state shape:

```swift
enum FocusGuardDemand: Equatable {
    case inactive
    case active(sessionID: UUID, bundleIdentifiers: Set<String>)
}
```

Including the session ID prevents stale work from one session winning after Stop or a new session starts.

### Controller integration

`FlowmoSessionController` derives demand from the committed `World` and reconciles:

- At startup, even if the loaded world did not change.
- After a successful local `Store.update`.
- After a successfully persisted timed transition.
- After an external `world.json` reload caused by CLI/agent activity.
- After pause and Continue, where phase alone does not change.
- After configuration changes.

Persist first, then reconcile. In particular, the existing `persistSync` failure path can advance only the controller's in-memory world; that uncommitted fallback must never activate the guard.

Do not call AppKit from `Engine`, inside the file lock, or from `Store`.

### View integration

Extend the existing single surface:

- Idle: compact Guard configuration control.
- Focus: small factual status only.
- Interception: inline message/actions without replacing the clock.
- Degraded state: concise truthful copy; never prevent Start or Focus.

Do not add a focus ring, duplicated timer, modal lock screen, dashboard, or setup flow.

## Checkable acceptance

- WHEN a legacy `world.json` has no Focus Guard field, THE SYSTEM SHALL load it with Focus Guard disabled.
- WHEN Focus Guard is disabled or has no selected apps, THE SYSTEM SHALL perform no interception in any phase.
- WHEN persisted state enters unpaused Focus with Focus Guard enabled, THE SYSTEM SHALL begin observing selected app activations.
- WHEN a selected app activates during guarded Focus, THE SYSTEM SHALL hide it, bring Flowmo forward, and offer Stay focused and Open once.
- WHEN Open once is chosen, THE SYSTEM SHALL allow that running app until it loses activation, then guard its next activation.
- WHEN an unselected app activates, THE SYSTEM SHALL leave it unchanged.
- WHEN Focus stops, is skipped, is cancelled, or becomes recovery-paused, THE SYSTEM SHALL stop guarding.
- WHEN a paused Focus is continued, THE SYSTEM SHALL resume guarding from the persisted configuration.
- WHEN the Flowmo window hides or closes during Focus, THE SYSTEM SHALL keep guarding.
- WHEN guarding fails, THE SYSTEM SHALL fail open, keep the Flowmo session valid, and avoid claiming that guarding is active.
- WHEN the Flowmo process exits or crashes, THE SYSTEM SHALL leave no persistent restriction behind.
- WHEN configuration changes, THE SYSTEM SHALL continue to use `world.json` as the only canonical Flowmo store.

## Proof plan

### Deterministic checks

- Legacy decoding and configuration round trips.
- Identifier normalization and forbidden-identifier filtering.
- Demand matrix across every phase × paused/unpaused × enabled/disabled × empty/nonempty selection.
- Idle-only configuration mutation.
- Startup, local transition, timed transition, Continue, Cancel, and external-reload reconciliation.
- Failed store writes cannot activate guarding.
- Fake-adapter idempotency and stale-session ordering.
- Open-once consumption and reset after deactivation.
- Adapter failure updates status without mutating session state.

### Manual checks

- Native app, Electron app, multi-window app, and full-screen app.
- Multiple processes sharing a bundle identifier.
- Selected app moved, updated, or uninstalled.
- Flowmo hidden and reopened.
- Stop, Skip, quit/Continue, sleep/wake, SIGINT, and SIGTERM.
- CLI-driven phase changes while the Flowmo process is running.
- `swift run` and the Dock app.

## Research record

The research supports a conservative framing:

- Digital self-control tools show small-to-medium short-term reductions in targeted technology use, but evidence is heterogeneous and often short-lived: [systematic review and meta-analysis](https://doi.org/10.1145/3571810), [systematic review](https://doi.org/10.1111/jcal.12581).
- Brief friction can reduce target-app consumption; deliberation copy alone appears weaker: [`one sec` study](https://doi.org/10.1073/pnas.2213114120).
- Voluntary, overridable limits can alter use: [soft-commitment experiment](https://doi.org/10.1016/j.euroecorev.2021.103924).
- Stronger lockouts can increase frustration, and harder is not consistently better: [GoalKeeper](https://doi.org/10.1145/3314403), [InteractOut](https://doi.org/10.1145/3613904.3642317).
- Reduced target-app use does not establish increased productivity, well-being, or flow.
- No direct evidence was found that a visible open-ended count-up causes people to focus or remain blocked longer. Do not claim a “subconscious challenge” mechanism.

Safe copy describes what the product does: it guards selected apps, adds a moment of friction, and shows elapsed time. Avoid “scientifically proven,” “improves productivity,” “deepens focus,” “rewires dopamine,” or similar claims.

## Platform record

Inspection of the current macOS SDK showed `ManagedSettings`, its application/web-domain shields, and `FamilyControls.AuthorizationCenter` marked unavailable on native macOS. The iOS Screen Time implementation used by apps such as ScreenFast is therefore not a native macOS path for Flowmo.

Relevant Apple documentation:

- [`NSWorkspace.didActivateApplicationNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
- [`NSRunningApplication.hide()`](https://developer.apple.com/documentation/appkit/nsrunningapplication/hide())
- [Family Controls](https://developer.apple.com/documentation/familycontrols)
- [Managed Settings](https://developer.apple.com/documentation/managedsettings)
- [Safari Web Extensions](https://developer.apple.com/documentation/safariservices/safari-web-extensions)
- [Network Extension entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)

Safari-site support would require a separate signed extension and user enablement. Cross-browser filtering would require a signed Network Extension/system-extension project. Neither belongs in this slice.

## Handoff order

1. Read `AGENTS.md`, `PROJECT.md`, and the current signed v1 artifacts.
2. Run the disposable feasibility spike.
3. If the spike passes, turn this handoff into a reviewed Focus Guard acceptance/design/tasks slice.
4. Implement Core configuration and proofs.
5. Implement the injectable adapter and controller reconciliation.
6. Add the compact UI.
7. Run deterministic checks and the manual lifecycle matrix.
8. Do not broaden the scope without another explicit product decision.
