# Flowmo — Focus Guard

Optional app friction during unpaused Focus. The loop and recovery behavior stay in [`PROJECT.md`](PROJECT.md).

---

## Outcome

Optional **Focus Guard**: when unpaused Focus is running, selected Mac apps get a moment of friction (hide + Flowmo comes forward + Stay focused / Open once). Off by default. Best-effort, not a lock.

Copy says what it does. Do not claim it improves productivity, well-being, or flow.

## Local instrumentation baseline

WP2 added Mac-only, best-effort instrumentation in a separate local
`evidence.json`. WP3 freezes a new `focus_guard_resumption_v1` plan containing
the original six paths plus aggregate eligibility and resumption outcomes:

- prompt offered after the selected app is confirmed hidden and Flowmo requests
  foreground presentation; this does not prove the prompt was visible or seen
- Stay focused chosen
- Open once chosen, atomically with one of the next two outcomes
- the same process-instance activation request accepted by macOS; this does not
  confirm that it became frontmost
- the Open once path not accepted because its identity no longer resolves or
  macOS declines the activation request
- interception failed and committed fail-open before a prompt was offered
- Stay focused resumption eligible or ineligible
- resumption not attempted because the treatment was already disabled
- exact-process activation request accepted or rejected
- matching activation confirmed within one second, or timed out
- resolution or activation identity mismatch

It stores no typed text, session ID, app identity, PID, bundle ID, path, raw
duration, or activity timestamp. It has no network dependency, analytics SDK,
or automatic upload. Turning Guard off stops new events but retains prior
counts. The user explicitly exports the aggregate report, and
**Delete All Data** removes the evidence store. Persistence failure may
undercount but must never reject, roll back, or change hiding, Stay focused,
Open once, or fail-open behavior.

Recording completeness is unknown. The recorder accepts at most 16 outstanding
writes and drops overflow, and counters may saturate at the maximum stated in
the report. Counts are therefore only possibly saturated lower bounds on paths
successfully observed by this recorder; they are not rates, exposure estimates,
population estimates, or estimates of actual technical-event volume.

A valid planned comparison exports predeclared start and end snapshots from the
same local evidence store under the same frozen measurement plan. The start must
actually precede the end, `generatedAt` must increase, no **Delete All Data**,
reset, or store replacement may intervene, and every end count must be at least
its start count. A counter at the declared cap is censored and cannot yield an
exact delta. Violating any condition invalidates the comparison. `generatedAt`
is export time, not an event timestamp. WP2 cannot establish that Guard causes
better learning, productivity, well-being, or focus.

Any change to event eligibility, emission timing, signal meaning, atomic counter
mapping, recorder admission/drop policy, or the counter/buffer caps must mint a
new measurement-plan identifier before collection. Do not merge counts across
plans.

The Idle screen keeps this explanation behind the quiet info control beside
Guard. It must not occupy persistent primary-loop chrome. Detailed limitations
belong in Data, the export itself, and the privacy documentation.

## Guard resumption engineering gate

WP3 may reduce the displacement created when Flowmo comes forward. Its code is
implemented, but the engineering gate has not yet passed. It is a
technical reliability gate, not a focus experiment: process identity can name a
prior app instance, not its document, window, or cognitive work context.

- **Eligible:** Stay focused is committed and the exact prior PID + bundle ID +
  launch identity still resolves.
- **Attempt:** request activation of that exact process instance once.
- **Confirmed:** observe a matching activation notification within the frozen
  one-second timeout; API acceptance alone is insufficient.
- **Safe fallback:** missing identity, mismatch, rejection, or timeout leaves
  today's Stay focused behavior intact and grants no exception.
- **Rollback:** any identity mismatch or unsafe fallback disables the treatment
  immediately for the remaining process lifetime. Guard keeps its baseline
  hide-and-prompt behavior.

The frozen acceptance plan is one supervised run of 60 eligible attempts within
30 days of the first eligible attempt. Smallest acceptable reliability is 95%
and maximum tolerable failure is 5%. A failure is rejection, timeout, activation
identity mismatch, or a missing terminal observation. The one-sided 95% exact
upper confidence bound on failure must also be below 5%; with 60 attempts that
requires zero failures. Identity mismatch or unsafe fallback rejects the
treatment immediately. A known recorder drop, counter saturation, store/export
problem, process crash, invalid start/end snapshot pair, or incomplete
eligible-to-terminal reconciliation invalidates the run. Fewer than 60 eligible
attempts is inconclusive. The supervised attempt tally must equal the exported
eligible delta; raw unsupervised counts cannot pass the gate.

Evaluate a completed supervised run with the repository-only engineering tool:

```bash
swift run flowmo-wp3-gate START.json END.json 60 \
  2026-08-25T09:00:00Z clean
```

The timestamp is the separately noted first eligible attempt, not an event
timestamp added to either export. Use `incident` instead of `clean` if the run
had a recorder, store, export, crash, or other integrity problem. The evaluator
checks the frozen plan and limits, snapshot chronology, 30-day window, exact
counter set, monotonicity, saturation, supervised tally, complete terminal
reconciliation, mismatch/rollback, and the fixed reliability rule. It exits 0
only for a pass, 1 for fail or invalid, 2 for inconclusive, and 64 for bad
arguments. It reads bounded regular files without following symlinks and does
not start, fabricate, or upload attempts.

WP2 reports only a possibly saturated lower bound on recorded Stay-focused
choices. That can inform rough feasibility, but WP3 measures its own eligibility
and WP2 did not select WP3's threshold. WP3 treatment counters remain
aggregate-only under the WP2 privacy contract and use a new plan identifier;
pre-WP3 counts are never merged. Neither technical reactivation nor fewer clicks
proves focus or productivity benefit.

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

WHEN a Guard outcome becomes eligible for local instrumentation \
THE SYSTEM SHALL commit the product state first, then enqueue exactly one typed
instrumentation event off the main actor.

WHEN an Open once path is accepted or not accepted \
THE SYSTEM SHALL increment Open once chosen and its one terminal outcome in the
same atomic evidence write.

WHEN Stay focused is committed and an exact prior unguarded process identity
still resolves \
THE SYSTEM SHALL request activation of that exact process once and SHALL NOT
grant an Open once exception.

WHEN Stay focused has no resolvable prior process identity or activation is
rejected or times out \
THE SYSTEM SHALL keep the selected app hidden, preserve the committed baseline
Stay focused behavior, and grant no exception.

WHEN a resumption request is accepted \
THE SYSTEM SHALL count success only after a matching PID + bundle identifier +
launch identity activation notification arrives within one second.

WHEN resolution or activation reports a different process identity \
THE SYSTEM SHALL cancel pending resumption and disable the resumption treatment
for the remaining process lifetime while leaving baseline Guard available.

WHEN Idle is shown \
THE SYSTEM SHALL make the counts explanation available on demand beside Guard
and SHALL NOT place it permanently in the primary interface.

WHEN evidence storage is busy, invalid, or unavailable \
THE SYSTEM SHALL drop the observation without changing the Guard outcome.

WHEN the user exports Focus Guard counts or confirms Delete All Data \
THE SYSTEM SHALL drain this process's queued observations first; lock contention
shall fail visibly rather than wait without a bound.

WHEN a paused Focus Continues  
THE SYSTEM SHALL resume guarding from persisted config.

WHEN the Flowmo window is hidden or closed during Focus  
THE SYSTEM SHALL keep guarding while the process lives.

WHEN hiding fails or the adapter errors  
THE SYSTEM SHALL fail open, keep the session valid, and not claim guarding is active.

WHEN the Flowmo process exits  
THE SYSTEM SHALL leave no persistent restriction.

THE SYSTEM SHALL NOT add a Pause control, a 0–100% focus ring, Home, tabs, a menu bar, or a second session store. The separate aggregate evidence file is never session state or a session controller.
