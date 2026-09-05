# Flowmo — iPhone

The iPhone app runs the same Core loop in its own native frame. The Mac window remains the main Mac product. Product rules stay in [`PROJECT.md`](PROJECT.md).

---

## Why iPhone first

| Later item | This slice |
|---|---|
| **iPhone** | Yes. Same loop, one native frame; active Focus expands into its Distant Horizon canvas. |
| Widgets | Read-only glance in the entitled target; absent from Flowmo Local. |
| History | Plain local completed-session list from Idle. |
| Theme packs | Charcoal, ink, and earned-rest gold from [`visual.md`](visual.md). Not a pack. |
| iCloud | Private CloudKit sync in the entitled target; absent from Flowmo Local. |
| Watch | Later. |

## Outcome

Both iPhone variants run:

Idle → type once → Prime (2:00) → Focus (count up, you stop) → earned Break → Reflection (3:00) → Close Beat → Idle.

A short, skippable **How it works** tutorial precedes the first safe Idle. It
is remembered per device, can be replayed from Data, and never starts or resumes
a session. Live sessions, recovery, and sync choices take precedence. See
[`PROJECT.md`](PROJECT.md#first-use-tutorial).

Kill the app → paused with **Continue** and **Restart**. Opening the app does not Continue by itself.

Copy does not claim productivity, well-being, or flow.

## Build variants

**Flowmo Local** is the chosen path for free Personal Team testing on the
owner's iPhone. This separate, Unreleased `FlowmoPhoneLocal` target and scheme
in `Apps/FlowmoPhone.xcodeproj` produces `FlowmoLocal.app`, displays **Flowmo
Local**, and uses bundle `app.flowmo.phone.local`. It stores
`Application Support/flowmo/world.json` inside its own app sandbox. It has no
App Group, CloudKit, push capability, background remote-notification mode, or
embedded widget. Local notification reminders remain available after opt-in.
The shared controller uses the local World authority without reading or
writing sync metadata, starting cloud transport, or refreshing widget timelines.

**FlowmoPhone** remains the entitled App Group/CloudKit/widget target. Its
existing store, private sync, and legacy migration behavior are unchanged.
Installing Flowmo Local does not read, import, migrate, or delete that target's
data. The two apps have separate History and tutorial preferences. A full
export is available for safekeeping; changing schemes is not a migration or
sync mechanism. Reinstalling the same app to refresh a provisioning profile
should preserve its container; deleting the app removes it, so export first.

Personal Team use requires the owner to select their team and run on a trusted
iPhone in Xcode. It is not public iPhone distribution. Signing, profile renewal,
and real-device notification delivery still need device verification; a
simulator build cannot prove them. See [`release.md`](release.md#free-personal-testing)
for installation constraints. Existing build 4 artifacts do not include this
new local variant.

## In

- New iOS app in **this** repo. Rules and JSON from **FlowmoCore**. New SwiftUI frame. **Not** AppKit `FlowmoWindow`. **Not** `~/Flowmo`.
- Same `world.json` schema, bounded validation, lock, and atomic write. Flowmo Local uses its own Application Support directory. The entitled target uses the phone/widget App Group container and synchronizes through the user's private CloudKit database; its widget only reads that App Group copy. Neither phone store is the Mac's `~/.flowmo`.
- Same controls as Mac: Start, Use next / Use last, restore a chosen Completed Session from History, Park thought, review parked thoughts into the Next Step, End focus, Reflect, Skip / Done, Restart, mute, and Idle-only Data controls. Close Beat Done carries that exact Session’s explicit Next Step into editable Idle without starting. **No pin.** **No Focus Guard.** **No menu bar.** **No `flowmo live`.**
- Same look rules: black field, ink on Start, determinate timed rings, and clock-in-ring on Prime/Break/Reflection. Gold is reserved for Break and earned rest. Active unpaused Focus uses a phone-native Distant Horizon with a count-up and earned-rest mark. No Focus progress ring. No Home. No tabs.
- Cues on by default (`cuesEnabled`). Mute silences sound. Optional local notifications announce timed endings while you are not looking. Only **Enable notifications** in the tutorial or Data requests permission; launch does not. Tap opens the app; it does not Continue.

## Out

Home, tabs, mandatory setup, scores, streaks, flashcards, SM-2, history dashboard, Watch, Live Activities, a second engine, Pause during Focus, App Store launch work. The optional tutorial does not add a Loop Beat.

## Phone vs Mac (honest)

The Mac Focus Scene is an optional movable, resizable window presentation. On
iPhone there is no desktop window to morph or return from, so the Distant
Horizon is the active unpaused Focus canvas itself. It keeps Park thought and
End focus available for touch. A Recovery Pause returns to the compact frozen
aperture with Continue and Restart.

On Mac, hide/close leaves Flowmo running. On iPhone, background **suspends** the process. Clocks stay honest because they are timestamps, not a ticking timer. Timed phases that should have ended while you were away catch up when Core `sync`s on the next launch or foreground.

Notification planning projects the persisted timestamps without writing a
second session. Prime schedules its end; Break schedules both its end and the
following Reflection end, so both can arrive during one uninterrupted period
in the background. Catch-up keeps only future deadlines. Early Reflect, Skip,
recovery, and later state changes replace the plan and cancel obsolete requests;
Continue uses the shifted persisted deadlines. Focus has no scheduled ending.
Muted requests omit sound. System permission and delivery policy still apply.
The UI/Core timer does not run continuously in the background. iOS may grant
`CKSyncEngine` bounded background execution for remote database notifications
in the entitled target only. Persisted timestamps remain the clock authority
when the interface returns.

## Checkable lines

WHEN this device has not skipped or finished the current tutorial
THE SYSTEM SHALL show the three-page tutorial at safe Idle, allow Skip on every
page, and return to editable Idle without starting. It SHALL defer during live
sessions, recovery, or a sync conflict, and SHALL offer replay from Data.

WHEN the user chooses Enable notifications in the tutorial or Data
THE SYSTEM SHALL request local-notification permission. Merely launching or
finishing the tutorial SHALL NOT request it or start a session.

WHEN the app is idle
THE SYSTEM SHALL show 00:00, Start, today’s Focus total, History, and Data. On a truly new store it SHALL explain count-up Focus and earned Break inside the aperture. When this phone just completed an exact Close Beat with a nonblank Next Step, Idle SHALL show that step as the editable Intention and SHALL NOT start. Otherwise, when available, Use next SHALL reveal only the latest Completed Session’s explicit Next Step for confirmation; Use last SHALL reveal the saved Intention.

WHEN the user opens History from Idle
THE SYSTEM SHALL show completed sessions newest-first. Each card shows intention, Focus duration, and local date. Tapping a card SHALL expand that session in place with Focused, Break earned, parked lines, and next step when present. An expanded card SHALL offer Use next step, or Use intention when that is the only cue; choosing it SHALL return to Idle with the line visible and SHALL NOT start automatically. If Idle already has a typed intention, the app SHALL ask before replacing it. Back SHALL return to Idle.

WHEN Reflection has parked thoughts and its next-step field is empty
THE SYSTEM SHALL offer a newest-first review inside the same frame. Use as next SHALL fill and persist the selected line as editable Reflection text without removing the parked line. Existing Reflection text SHALL never be overwritten.

WHEN the user taps Done on an unpaused Close Beat
THE SYSTEM SHALL complete that exact session once. If its Reflection next step
is nonblank, the phone SHALL return to Idle with that exact trimmed text in the
editable intention field and SHALL NOT start Prime. A blank next step SHALL
leave Idle empty, and a stale Done action SHALL NOT advance a replacement
session or borrow a cue from older History.

WHEN the user starts
THE SYSTEM SHALL enter Prime for 120s with that intention and SHALL NOT ask for it again during Prime.

WHEN an active unpaused Focus is showing and no recovery or sync decision supersedes it
THE SYSTEM SHALL fill the phone frame with the Distant Horizon, count up from timestamps, show earned rest, offer Park thought and End focus, and SHALL NOT show Pause, a 0–100% focus ring, Home, or tabs. The horizon SHALL remain ambient geometry rather than progress. Capture SHALL stay on the canvas with Discard and Park.

WHEN the user backgrounds the app during a live session
THE SYSTEM SHALL not pause. On return the same phase is still moving (or already advanced if a timed beat ran out).

WHEN a session arrives from the Mac through private CloudKit in the entitled target
THE SYSTEM SHALL display the same timestamped session and SHALL NOT pause it as
an iPhone process-recovery event. Retry after store repair SHALL preserve exact
remote ownership too; stale ownership after a local change SHALL still recover
paused.

WHEN entitled devices start or ambiguously change a session while offline
THE SYSTEM SHALL block loop controls and require **Keep this iPhone** or **Use
iCloud version**. It SHALL NOT silently merge two live sessions.

WHEN CloudKit is signed out or unavailable in the entitled target
THE SYSTEM SHALL remain usable against its local store and queue later sync.
Changing iCloud accounts SHALL require an explicit data choice before upload.
A missing iCloud account or entitlement SHALL NOT occupy the session interface;
structural or unknown sync failures, pending deletion, and account-choice
problems remain visible.

WHEN the process is killed during a live session
THE SYSTEM SHALL restore paused with Continue and Restart. Appearing SHALL NOT resume. Restart SHALL drop the frozen session and start Prime with the same intention.

WHEN a timed phase (Prime, Break, Reflection) will end while the app is not foreground
THE SYSTEM SHALL schedule a local notification for that end, subject to system
permission. Break SHALL also schedule the following Reflection end before
suspension. Skip, Stop, recovery, or an earlier phase change SHALL cancel or
replace obsolete deadlines. Activating a notification SHALL open the app and
SHALL NOT Continue.

WHEN larger accessibility text or a short available height constrains a compact beat
THE SYSTEM SHALL allow the phase column to scroll and its caption/action rows
to grow. Idle footer actions SHALL have at least 44×44pt touch targets; Today
SHALL move above them when the combined row does not fit. The first-session
reminder, Data, and tutorial SHALL remain readable without adding navigation.

WHEN `world.json` is a Mac-shaped document
THE SYSTEM SHALL load it. Guard fields have no iPhone UI.

WHEN the entitled target's App Group container is unavailable
THE SYSTEM SHALL show a calm unavailable state with Retry and SHALL NOT crash or
fall back to a different store.

WHEN Flowmo Local's Application Support directory is unavailable
THE SYSTEM SHALL show a calm unavailable state with Retry and SHALL NOT resolve
the App Group or fall back to another store.

WHEN either variant's selected store is invalid
THE SYSTEM SHALL offer Retry, redacted diagnostics, or Preserve & Reset. The
original bytes SHALL be preserved before reset.

WHEN the user opens Data from Idle
THE SYSTEM SHALL offer full export, redacted diagnostic export, and explicitly
confirmed Delete All whose confirmation names that variant's deletion scope.
Data SHALL also offer How it works and Enable notifications. Delete All SHALL
remove the selected store's Flowmo-owned recovery copies. In Flowmo Local it
SHALL affect only that app's local data, without iCloud deletion or widget
refresh. In the entitled target it SHALL name local and synced iCloud data,
reload the widget timeline, remove local private sync replicas immediately,
and report incomplete deletion until queued CloudKit deletion is confirmed.
