# Flowmo architecture

This document describes technical ownership and the seams new work must cross.
[`PROJECT.md`](PROJECT.md) remains authoritative for product behavior, and
[`CONTEXT.md`](../CONTEXT.md) defines the domain vocabulary used here.

## Shape of the system

Flowmo has one domain and several adapters around it:

```text
Mac host ----> FlowmoWindow ----+----> FlowmoCore
                                +----> FlowmoLook ----> FlowmoCore
                                +----> FlowmoSync ----> FlowmoCore
                                                  \
                                                   +-> CloudKit

Phone hosts -> FlowmoPhone -----+----> FlowmoCore
                                +----> FlowmoLook
                                +----> FlowmoSync (entitled mode only at runtime)

FlowmoCLI / checks / gate ------------> FlowmoCore
```

Dependencies point toward `FlowmoCore`. AppKit, SwiftUI lifecycle, CloudKit,
notifications, and process activation do not belong in the domain module.

| Module | Owns | Does not own |
|---|---|---|
| `FlowmoCore` | Loop state, transitions, timestamp-derived clocks, action-first World commits, validation, and the local `World` store | UI, CloudKit transport, app activation |
| `FlowmoSync` | Reconciliation, synchronized World persistence, sync metadata, record encoding, and the CloudKit adapter | Session rules or an independent copy of `World` |
| `FlowmoLook` | Shared visual primitives, Distant Horizon backdrop, and tutorial page/completion presentation | Session authority or platform routing |
| `FlowmoWindow` | Mac presentation, lifecycle, Focus Guard adapter, Focus Scene, and Work Handoff | Domain transitions or direct file mutation |
| `FlowmoPhone` | Phone presentation, including its active-Focus Distant Horizon, lifecycle, attention, explicit store-mode selection, and entitled-mode widget coordination | A second phone-specific session model |
| `FlowmoCLI` | Supported terminal commands and versioned JSON projections | Direct JSON editing |
| App hosts | Bundle configuration, entitlements, and platform packaging | Product rules |

`FlowmoWindow` and `FlowmoPhone` currently contain broad orchestration
controllers. Treat those as migration surfaces, not as permission to add new
domain policy there.

### iPhone host configuration

Two explicit hosts reuse `FlowmoPhone` and the same Core rules. The existing
[`FlowmoPhone.swift`](../Apps/FlowmoPhone.swift) selects the default
`PhoneStoreMode.sharedWithWidget`: its App Group store, synchronized authority,
CloudKit lifecycle, and widget reloads remain unchanged. A missing App Group
fails closed. Its validated legacy Application Support migration remains a
dedicated Store maintenance path within that app's container.

The separate, Unreleased [`FlowmoPhoneLocal.swift`](../Apps/FlowmoPhoneLocal.swift)
selects `.localOnly` through `PhoneStoreBootstrap`. The `FlowmoPhoneLocal`
target/scheme uses bundle `app.flowmo.phone.local`, product `FlowmoLocal.app`,
and its own sandbox's `Application Support/flowmo/world.json`. Store selection
returns this path before resolving an App Group or invoking migration. Missing
Application Support fails closed; invalid data remains in that selected store
for the ordinary repair flow. There is no fallback or transfer between variants.

Local mode uses `WorldAuthority(store:)`, never starts CloudKit or reads/writes
sync metadata, and skips widget reloads and cloud deletion. The shared module
still imports `FlowmoSync`; linking it does not enable transport. The local
host declares no App Group, iCloud, push, or remote-notification background
capability and embeds no widget. Its own privacy manifest declares no collected
data or tracking. Tutorial preferences belong to its bundle; local reminders,
exports, recovery, and History reuse the same implementations. See
[`iphone.md`](iphone.md#build-variants) and [`PRIVACY.md`](../PRIVACY.md).

## State ownership

There is one authoritative `World` per local store. Its timestamps, not UI
ticks, determine clocks and timed transitions.

| State | Rule and persistence ownership | Writers |
|---|---|---|
| `world.json` | `Engine` for Loop rules, `FlowmoSync` for reconciliation, and `Store` for validation and maintenance | The local World mutation seam or a dedicated locked `Store` maintenance operation |
| `sync/state.json` and sync assets | `FlowmoSync`; not used by Flowmo Local | Sync metadata store and CloudKit adapter |
| Mac process-recovery marker | Mac lifecycle recovery | Recovery adapter in its documented lock-held write-ahead and post-persist order |
| Focus Guard evidence | Local evidence recorder | Focus Guard evidence adapter only |
| Display preferences | Platform presentation | Mac or phone presentation code |
| Tutorial completion version | Device-local app `UserDefaults`, outside `World` and CloudKit | Shared `IntroductionState`; Skip and finish mark completion, replay changes presentation only |
| Mac Focus Scene and Work Handoff state | Current Mac process | `FlowmoWindow`; never persisted into `World` |
| Phone Distant Horizon selection | Derived presentation state | `FlowmoPhone` derives it from the current unpaused Focus and blocking recovery/conflict facts; never persisted into `World` |

The widget is a read-only projection. Glances may navigate to the main product,
but they never issue Session actions or resume a Recovery Pause; a living view
may persist legitimate timestamp-derived catch-up through the World mutation
seam.

## The World mutation seam

`Engine` is the single implementation of Loop behavior. Do not create a second
state machine in a controller, sync adapter, or repository. `WorldAuthority`
is the action-first interface over that same Engine and the atomic local
read-modify-write under `world.lock`. `Store.update` remains the local authority
adapter's implementation mechanism and an explicitly documented route for
selected non-action transactions; it is not an ordinary action interface. Every
ordinary production `Engine` `Event` mutation crosses the authority seam.
Invalid-data quarantine, Idle-only reset, privacy deletion, and validated
one-time entitled phone-store migration remain dedicated locked `Store`
maintenance operations. Flowmo Local has no migration path from the entitled
app's store.

The implemented action interface has one overload for a caller that targets
the locked current World and one for a visual adapter that targets the exact
Live Session it displayed:

```swift
let result = try authority.apply(event, at: timestamp)

let result = try authority.apply(
    event,
    observed: ObservedLiveBeat(
        sessionID: displayedSessionID,
        beat: displayedBeat,
        isRecoveryPaused: displayedRecoveryState
    ),
    at: timestamp
)
```

The result is either a durable `WorldCommit` or a stale observation carrying
the locked current World. A commit includes before/after Live Beat facts, the
exact newly Completed Session when applicable, whether World changed, and a
warning when related persistence failed after World became durable. Callers
adopt the returned World before running presentation effects or surfacing that
warning.

The entitled phone's exact Continue, Restart, and Close Beat actions cross the
synchronized authority adapter, which retains `sync.lock` inside `world.lock`
when it can update local ownership. Flowmo Local routes the same actions through
the local Store authority, without the sync lock or metadata. The concrete `@MainActor`
`MacWorldAuthority` now defines the Mac action shape for exact observed actions,
current-World actions, and exact Prime-to-Focus Work Handoff. It returns typed
stale, durable, sync-warning, post-persist recovery-block, and pre-persist
no-commit outcomes while preserving the recovery marker order below. The Mac
and phone controllers' ordinary Engine `Event` actions now cross this authority.
Visual Live Session gestures carry the exact displayed observation; Idle and
configuration actions target the locked current World. The nonvisual CLI's
action verbs also target the locked current World and adopt the committed World
for their unchanged human and JSON projections. Timed catch-up,
presentation-only validation, lifecycle claim and pause, maintenance,
remote-reconciliation, and conflict routes retain their existing dedicated
transactions. Those uncommon routes may move only when typed operations
preserve their current contracts. The ordinary action extraction is complete;
it did not create a parallel engine or require a repository-wide rewrite.

The seam maintains these invariants:

- Every event and recovery mutation receives an explicit timestamp.
- Stale-sensitive actions compare the observed Live Session, Loop Beat, and
  Recovery Pause state while holding the same lock as the write.
- Remote reconciliation is recomputed against the latest local `World` inside
  the transaction; a snapshot loaded before the transaction is never saved over
  a newer local action.
- A Session Conflict choice carries the exact displayed conflict and is
  accepted only while that conflict and the current remote facts still match
  what was presented.
- Sync reconciliation acquires `sync.lock` only after `world.lock` and retains
  that metadata lease from its read through World persistence and the matching
  metadata save. Another metadata writer cannot invalidate or overwrite the
  plan between those operations.
- Remote ownership is valid only for the exact Live Session snapshot applied or
  staged from remote work; a same-ID local mutation cannot suppress Recovery
  Pause after a metadata-write failure. Entitled phone Retry checks that ownership
  against the current Session while holding the World transaction lock before
  deciding whether store recovery should pause it.
- Success means the resulting `World` is durable.
- Mac recovery uses a documented mixed order while `world.lock` is held:
  write-ahead observation precedes persistence of a live-session change, while
  terminal clearing and remote-to-local ownership adoption happen only after
  the matching `World` is durable. A post-persist failure does not imply that
  `World` rolled back.
- CloudKit requests, view updates, sound, Focus Scene, and Focus Guard run after
  the transaction and outside the lock.
- Sync transport staging and status finish before a committed World is sent to
  a UI adapter, so actor reentrancy cannot resume an older operation and stage
  or publish it over newer sync state.
- Work Handoff is a narrow post-persist exception: activation runs while the
  lock is still held so a competing local writer cannot end or replace the
  exact Focus before its handoff. It is bounded, fail-open, and cannot mutate
  `World`. Do not generalize this into an arbitrary transaction callback.

Sync metadata is not yet stored in one atomic envelope with `World`. Until that
migration is justified and proved, reconciliation and local-ownership commits
that touch both files hold `world.lock` and the nested `sync.lock` lease,
persist `World` first, then persist derived metadata before releasing either
lock. This avoids stale World and metadata overwrites. A filesystem failure can
still leave a durable World and older metadata; the sync adapter adopts the
durable World, reports unavailable, and later reconciliation repairs that
divergence. It is not an atomic two-file commit.

Privacy deletion is a deliberate staged maintenance exception, not a
reconciliation commit. It deletes or resets the local World under its own lock,
then coordinates recovery-marker cleanup and, in sync-capable builds, sync
deletion intent and CloudKit deletion in separate bounded steps. Flowmo Local
finishes after its own local cleanup without queuing cloud deletion. Partial
completion stays visible as an incomplete-deletion state; no remote call holds
`world.lock`.

The accepted decision and its tradeoffs are recorded in
[`adr/0001-single-world-mutation-authority.md`](adr/0001-single-world-mutation-authority.md).

## Interfaces and adapters

Create an interface when it protects a real external or local-substitutable
seam:

- `WorldAuthority` has a package-internal persistence seam with two real
  adapters: the local `Store` adapter and the synchronized World-plus-metadata
  adapter. Feature callers cannot inject arbitrary lock-held callbacks.
- `MacWorldAuthority` is a concrete actor-isolated module rather than a
  protocol-shaped controller. Its recovery persistence seam has the real
  synchronized process marker and a recording test adapter; Work Handoff keeps
  its existing AppKit adapter. No caller can provide a generic transaction
  callback.
- CloudKit is external. Keep transport behind the `FlowmoSync` adapter and test
  reconciliation without a network account.
- The filesystem and process-recovery marker are local-substitutable. Tests may
  use isolated roots or recording adapters.
- Notifications, widgets, Scene windows, and ordinary AppKit presentation are
  platform adapters after the transaction. The exact-session Work Handoff
  ordering above is the sole AppKit exception.

Do not add a protocol merely to rename an implementation. A useful module has
depth: its small interface hides validation, ordering, persistence, or platform
policy that callers would otherwise duplicate.

## Tutorial and attention presentation

`IntroductionState` and `IntroductionView` in `FlowmoLook` own the three tutorial
pages and a versioned app-local completion preference. Controllers inject the
preferences, forward presentation changes, and allow the tutorial only at Idle
without store/lifecycle recovery or a sync conflict. Root views reevaluate that
eligibility as state changes. Mac window sizing temporarily presents Classic
without changing the saved Mini preference. Tutorial actions do not cross the
World mutation seam; the only optional external effect is a user-selected
notification-permission request through the platform attention adapter.

`PhoneNotificationPlan` is a pure projection over `World` and a timestamp. It
uses Core catch-up on a temporary Engine to enumerate the remaining known
timed boundaries: at most Break end and Reflection end. It neither persists
that projection nor invents a Focus deadline. `PhoneAttention` cancels its
owned legacy/phase request identifiers and serializes new additions after any
in-flight work, so a stale addition cannot survive a newer plan's cancellation.
Controllers reconcile after committed state changes, foreground catch-up, sync,
and recovery. Notification delivery remains an operating-system effect, not
evidence that the app kept executing while suspended.

## Landing a feature

1. Start from the behavior document and terminology in `CONTEXT.md`.
2. Use [`feature-map.md`](feature-map.md) to locate the owning module and the
   real-user proof. Update the map only when ownership or proof routing changes.
3. Put new Loop rules in `Engine`; put a new platform interaction in its
   adapter. Keep presentation decisions in the surface module.
4. Route every ordinary World change through the mutation seam. Use the
   dedicated locked `Store` maintenance operations only for invalid-data
   quarantine, Idle-only reset, privacy deletion, and validated one-time store
   migration; never compose `load`/modify/`save` in a caller.
5. Add the narrowest regression proof in the owning module, then run the related
   host or user-surface proof. A module test does not prove a platform
   interaction.
6. Update `CHANGELOG.md` only for tester-visible behavior. Architecture-only
   refactors should leave product language unchanged.

Prefer a vertical change with one owner over a new cross-module manager. Split
large files only when the extracted module gains a coherent interface and
ownership; line count alone is not an architectural seam.

## Current pressure points

- The phone and Mac controllers and the CLI delegate ordinary Engine `Event`
  actions to `WorldAuthority` or `MacWorldAuthority`. Exact-observation checks
  and completion facts remain available to visual surfaces; the CLI deliberately
  targets the current locked World. Timed catch-up and uncommon lifecycle,
  maintenance, reconciliation, conflict, and presentation-validation
  transactions remain separate. Draft, presentation, and output handling stay
  surface-owned.
- `FlowmoCore` still mixes domain types with persistence and some supporting
  utilities. Separate them only along proven dependency seams; keep `Engine`
  behavior stable during that work.
- `FlowmoCheck` overlaps parts of XCTest. Keep it as a compact executable smoke
  proof and put detailed regression coverage in test targets.
- Cross-module moves should follow an established seam and ship as a dedicated
  change, separate from new product behavior.
