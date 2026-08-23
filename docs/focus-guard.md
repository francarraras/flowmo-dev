# Flowmo — Focus Guard

Optional app friction during unpaused Focus. The loop and recovery behavior stay in [`PROJECT.md`](PROJECT.md).

---

## Outcome

Optional **Focus Guard**: when unpaused Focus is running, selected Mac apps get a moment of friction (hide + Flowmo comes forward + Stay focused / Open once). Off by default. Best-effort, not a lock.

Copy says what it does. Do not claim it improves productivity, well-being, or flow.

## In

- One remembered set of `.app` bundles (bundle IDs in `world.json`).
- Configure from **Idle** in the existing frame. No Home, tabs, second window, or wizard.
- Guard only during **unpaused Focus**. Prime, break, recall, close beat, idle: off.
- Hide + bring Flowmo forward. **Stay focused** / **Open once** (that exact process instance until it loses activation).
- Small factual Focus line (`Guarding 3 apps`). Clock stays the hero. No extra ring.
- Same Core store. `swift run` and the Dock app, if the spike proves both.
- Fail open. Crash/quit leaves no OS restriction.

## Out

Websites, Screen Time / Family Controls, Accessibility, killing processes, helpers, extensions, hard blocks, schedules, lists, scores, history, claims, CLI as the config UI.

## Checkable lines

WHEN a legacy `world.json` has no Focus Guard field  
THE SYSTEM SHALL load with Guard disabled and an empty list.

WHEN Guard is off or the list is empty  
THE SYSTEM SHALL intercept nothing in any phase.

WHEN persisted state is unpaused Focus, Guard is on, and the list is nonempty  
THE SYSTEM SHALL observe selected app activations.

WHEN a selected app activates during guarded Focus  
THE SYSTEM SHALL hide it, bring Flowmo forward, and offer Stay focused and Open once.

WHEN Open once is chosen  
THE SYSTEM SHALL bind the exception to PID + bundle identifier + launch identity,
allow that exact running process until it deactivates, and never transfer the
exception to a process that reuses its PID.

WHEN guarding becomes active or its session/selection changes
THE SYSTEM SHALL evaluate the current frontmost application once and SHALL
reject retries belonging to an older demand generation.

WHEN Focus stops, skips, cancels, or recovery-pauses  
THE SYSTEM SHALL stop guarding.

WHEN a paused Focus Continues  
THE SYSTEM SHALL resume guarding from persisted config.

WHEN the Flowmo window is hidden or closed during Focus  
THE SYSTEM SHALL keep guarding while the process lives.

WHEN hiding fails or the adapter errors  
THE SYSTEM SHALL fail open, keep the session valid, and not claim guarding is active.

WHEN the Flowmo process exits  
THE SYSTEM SHALL leave no persistent restriction.

THE SYSTEM SHALL NOT add a Pause control, a 0–100% focus ring, Home, tabs, a menu bar, or a second store.
