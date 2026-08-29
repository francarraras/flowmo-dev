# ADR 0001: One World mutation authority

Technical context and the current compatibility seam are described in
[`../architecture.md`](../architecture.md).

- Status: Accepted
- Date: 2026-08-28

## Context

Flowmo has one Live Session per local store. Mac, phone, CLI, recovery, and sync
all need to change the same persisted `World`, while clocks and stale-action
checks depend on persisted timestamps. Controllers currently repeat some
preconditions, and Cloud reconciliation has historically composed a separate
load and save. That permits a newer local action to be overwritten by a result
computed from stale state.

`Engine` already contains the product state machine, and `Store.update` already
provides a cross-process locked read-modify-write. Replacing either wholesale
would add risk without adding product value.

## Decision

There will be one action-first World mutation authority over the existing
`Engine` and local transaction. Every ordinary production `World` writer must
cross this seam. Dedicated locked `Store` operations remain the route for
invalid-data quarantine, Idle-only reset, privacy deletion, and validated
one-time phone-store migration until typed maintenance commits replace them.
The authority will:

- take explicit timestamps;
- atomically validate observed Live Session and Loop Beat state for stale-sensitive
  actions;
- apply Loop behavior through `Engine` exactly once;
- reconcile remote facts against the latest local `World` while holding the
  local lock;
- acquire `sync.lock` only inside `world.lock` and retain that lease from the
  metadata read through World persistence and the matching metadata save;
- return committed state and transition facts for callers to adopt;
- exclude CloudKit, UI, Scene, sound, and other unbounded external effects from
  the transaction; and
- retain only documented, bounded lock-held side effects whose ordering is part
  of correctness: the Mac recovery marker's write-ahead/post-persist sequence
  and exact-session Work Handoff. Mac recovery may change `World` only through
  its explicit Engine recovery contract; Work Handoff cannot mutate `World`
  and is fail-open.

The authority will be extracted incrementally. Until that interface exists,
`Store.update` is its compatibility seam and direct `World` load/modify/save
sequences are prohibited.

`World` and sync metadata remain separate files for now. A reconciliation or
local-ownership commit involving both holds the ordered `world.lock` then
`sync.lock` pair, persists `World` first, then metadata, and releases the nested
metadata lease before a successful World transaction returns. Privacy deletion
is deliberately staged: local World deletion/reset completes under its own
lock, then recovery-marker cleanup, durable sync deletion intent, and CloudKit
deletion proceed separately with incomplete deletion surfaced to the person.
Introducing a combined envelope or write-ahead journal requires a separate
decision with migration, crash-recovery, deletion, and privacy proofs.

## Consequences

- `Engine` remains the sole domain state machine.
- New adapters cannot replace `World` from a precomputed stale snapshot.
- A remote-ownership marker names an exact Live Session snapshot, not only a
  reusable session identifier.
- Mac and phone orchestration can converge behind a small, high-leverage
  interface without merging their presentation code.
- Ordinary post-commit platform effects may fail independently but cannot
  corrupt the Live Session. The recovery-marker sequence and Work Handoff stay
  small and explicitly proved because their lock-held ordering carries extra
  contention risk.
- The interim two-file ordering is not full crash atomicity. It favors a
  durable World plus recoverable sync work; a future aggregate transaction may
  remove that limitation.
- Large controller and file splits are deferred until the authority seam makes
  ownership local and mechanically checkable.
