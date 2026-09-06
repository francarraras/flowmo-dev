# Privacy

Last updated: 2026-09-06

Flowmo does not currently operate a server and contains no third-party
analytics, advertising, or crash-reporting SDK. The entitled Mac and iPhone
apps transmit session data only to Apple's CloudKit service for private
cross-device synchronization. Flowmo does not transmit it to a developer-run
server. The separate **Flowmo Local** iPhone app does not start CloudKit or
transmit session data. It is the local-only variant for free Personal Team
testing; the selected distribution scope does not require paid Apple Developer
membership. The entitled targets remain in the source for eligible contributors.

## Data kept on the device

Flowmo stores the current session, intentions, parked thoughts, Reflection text,
completed-session history, cue preference, fixed break ratio, and selected
Focus Guard application identifiers. The Mac store is normally
`~/.flowmo/world.json`; `FLOWMO_HOME` is a development override. The entitled
`FlowmoPhone` app and widget use the private `group.app.flowmo.phone` App Group
container. **Flowmo Local** (`FlowmoPhoneLocal`, bundle `app.flowmo.phone.local`)
instead stores `Application Support/flowmo/world.json` in its own app sandbox.
It has no App Group or Home Screen widget, does not resolve or migrate the
entitled app's store, and cannot sync or delete that other app's data. Missing
local storage produces an unavailable state; it never silently switches storage locations.
Deleting the app removes its container, so export first to keep a copy. Flowmo's
local-only mode does not configure or disable the operating system's device
backup service.

Mac and iPhone also keep a tutorial-completion version in the app's local
preferences, so skipping or finishing the introduction prevents automatic
repetition. This preference contains no session content, is not added to
CloudKit or exports, and is not used for analytics. Tutorial pages and replay
state are temporary UI state. Deleting session data leaves this presentation
preference intact; **Data → How it works** remains available for replay.

Sync-capable Mac and phone builds also keep bounded sync metadata beside their
local store. Flowmo Local does not read or write that metadata. Sync metadata
can include a validated local or remote session replica, a durable outgoing queue, opaque CloudKit record change tags, a random account-scoped
identifier supplied by CloudKit, and a session identifier used to distinguish a
remote live session from local crash recovery. Files use mode 0600 where the
platform permits it. Temporary CloudKit assets are exact UUID-named transport
copies and are removed after upload.

## Private iCloud synchronization

This section describes eligible entitled builds, not Flowmo Local. The local
iPhone app has no iCloud or push capability and does not queue uploads even
when the phone is signed in to iCloud.

Entitled Flowmo uses container `iCloud.app.flowmo` and only the signed-in user's
private CloudKit database. It sends the live phase and timestamps, intentions, parked
thoughts, Reflection text, fixed break ratio, and completed-session history so the
same loop can appear on Mac and iPhone. Sync is app functionality only. It is
not used for analytics, advertising, marketing, profiling, or tracking.

Apple documents that [private-database
content](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)
belongs to the user, counts against the user's iCloud quota, is accessible only
to that user by default, and is not visible in the developer portal. Data is
unavailable to another iCloud account unless the person explicitly chooses what
to keep after an account change. Flowmo uses random revisions rather than
content hashes and keeps private text out of logs and diagnostics.

Local operation continues when iCloud is signed out or unavailable. Changes are
queued for a later attempt. If two devices create incompatible live sessions or
other ambiguous changes while offline, Flowmo blocks session controls and asks
which copy to keep instead of silently overwriting or combining them. Distinct
completed sessions can merge by their random session identifiers.

The Home Screen widget does not access CloudKit. It remains a read-only glance
over the entitled iPhone App Group store. It does not read Flowmo Local's store.
The command-line and `swift run` launchers do
not carry CloudKit entitlements; their Mac-store changes synchronize when the
entitled Mac app observes them or next opens.

Flowmo Local's separate `FlowmoFocusActivity` extension displays a read-only
Focus clock on the Lock Screen and supported Dynamic Island. The app gives
ActivityKit only the random session identifier and Focus start timestamp. No
intention, parked thought, Reflection text, history, or store path is included.
The extension does not read the app's store and has no App Group, CloudKit, or
push capability. It uses the supplied timestamp for the system-rendered clock;
it does not create a network service or upload data. The visible clock may be
seen by someone looking at the phone. Tapping it opens Flowmo; it does not
control or resume the session. The app ends this display when it reconciles
Focus ending, recovery, or a blocked store; system dismissal does not delete
the underlying session.

According to system settings, iOS may also mirror this metadata-only display to
a paired Apple Watch or Mac, or show it in CarPlay. This is Apple's system
presentation, not a new Flowmo Watch app, custom Mac activity surface, or
app-run sync/network service. See [Apple's ActivityKit overview](https://developer.apple.com/documentation/activitykit).

App-local preferences keep the current ActivityKit identifier, its session
identifier, and one session dismissal marker so the app does not recreate a
removed reminder. They contain no written text, are excluded from session
exports and CloudKit, and are cleared by explicit Delete All. The extension's
[`privacy manifest`](Apps/FlowmoFocusActivity/PrivacyInfo.xcprivacy) declares no
collected data, tracking, or required-reason API access; it does not read the
app's files or preferences.

On Mac, Work Handoff observes local application activation only to
remember the most recently active regular app before Start. It keeps that exact
running-app target only in process memory for the live session and may ask macOS
to reactivate it after the user explicitly chooses **Focus now**. It does not
persist or log the app identity, URL, file path, document or window title,
browser tab, or content.

On Mac, Focus Guard observes local application activation only to hide apps the
user selected during Focus. It does not use Accessibility control, terminate
processes, or send application activity anywhere. Flowmo may also ask the
operating system for local-notification permission and play system sounds.
Permission is requested only when the person chooses **Enable notifications**
in the tutorial or Data. Scheduled phone notifications contain generic phase
messages and deadlines, never an intention, parked thought, or Reflection text.

The local JSON file is internal storage, not a supported write API. Automation
should use supported CLI commands.

The Mac, entitled iPhone, and widget bundles include a shared Apple privacy
manifest. It declares no tracking. Conservatively, it declares Other User Content and Product
Interaction as linked data used only for app functionality because the entitled
apps retain the loop in the user's private iCloud account. It also declares
required-reason code `C617.1` because Flowmo inspects the size and type of files
inside its own app and App Group containers to read local stores safely. That
file metadata is not sent to Flowmo or used for tracking.

The shared manifest also declares UserDefaults reason `CA92.1` for app-only
presentation preferences such as tutorial completion and Mac display mode,
consistent with [Apple's approved API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
These preferences are not shared through App Group defaults.

Flowmo Local includes a separate
[`privacy manifest`](Apps/FlowmoPhoneLocal/PrivacyInfo.xcprivacy) declaring no
collected data and no tracking. It declares the same `C617.1` and `CA92.1`
reasons for safe local file access and app-only presentation preferences.
Its tutorial completion and notification permission belong to its own app;
installing the other variant does not transfer them.

On Mac, a small local lifecycle marker stores a process identity, the current
session identifier (not its text), and an observation timestamp so a crash or
quit cannot silently advance a session. A terminal transition or successful
data deletion clears the prior session identifier.

The Mac app also keeps a separate local `evidence.json` containing bounded
aggregate Focus Guard path counters. They cover prompt, Stay focused, Open once,
hide/activation failure, whether an exact prior process was eligible for the
resumption treatment, and whether its activation was accepted, rejected,
confirmed by a matching notification, timed out, or produced an identity
mismatch, plus whether a later attempt was withheld after treatment rollback.
It does not contain typed text, session identifiers,
app identity, process identifiers, bundle identifiers, store paths, raw
durations, or event/activity timestamps. The report's `generatedAt` is export
time, not an activity time.

The counters are best-effort: completeness is unknown, writes may be lost if
the app exits, persistence is unavailable, or the fixed 16-write recorder
buffer is full, and each counter saturates at the maximum declared in the
export. Evidence failure never rejects, rolls back, or changes a session or
Focus Guard action. Process identity used for Guard and resumption exists only
transiently in memory and is never written to this evidence file. Turning Guard
off stops new events but does not erase prior counts; they remain on the Mac
until **Delete All Data**. This foundation is not present in either iPhone
variant's store.

## Diagnostics and exports

Flowmo records privacy-safe issue codes in Apple's local unified logging system.
It does not log intentions, parked thoughts, Reflection text, selected application
identifiers, or store paths. A user can explicitly export a redacted diagnostic
JSON report containing app/build/OS metadata, the current phase, counts, and
recent issue codes with their operation categories and timestamps. The report
is never uploaded automatically.

A separate full-data export contains the user's private Flowmo text and history.
The user chooses where to save and share it.

The user may separately and explicitly export the aggregate Focus Guard counts.
Flowmo never uploads them automatically. Raw counts are not valid rates and
cannot establish that Flowmo or Focus Guard causes better learning,
productivity, well-being, or focus. If a tester voluntarily shares an export,
the recipient or sharing channel may still identify the sender even though the
JSON contains no user identifier; any research collection needs a separate
consent, retention, and deletion protocol.

Repairing an invalid store preserves the original bytes in a local quarantine
before resetting the app. The separately confirmed **Delete All Data** action is
available only while idle and removes current Flowmo data plus exact Flowmo-owned
quarantine and crash-write recovery artifacts. On Mac this includes the
separate evidence store and its owned recovery artifacts. Cleanup is non-recursive; if
an artifact cannot be removed safely, Flowmo reports that deletion is incomplete
instead of claiming success.

In Flowmo Local, export and Delete All apply only to that app's own local data
and recovery copies. Deletion never contacts CloudKit or creates a pending
cloud-deletion request. A full export is a user-controlled copy, not automatic
migration or sync between variants.

In entitled builds, Delete All removes private session replicas from the device
immediately and queues deletion of their records from the user's private CloudKit database.
Only opaque record identifiers and change tags needed to finish that deletion
remain locally while it is pending. If the device is offline, signed out, or
CloudKit rejects the operation, Flowmo says deletion is incomplete; it does not
claim the cloud copy is gone. The user can retry after CloudKit is available.

## Apple beta services

An external TestFlight beta is not active. If it is enabled, Apple automatically
collects TestFlight crash logs and usage information and shares eligible reports
with the developer; testers cannot opt out of that TestFlight collection. This
is separate from Flowmo's own code. See [Apple's TestFlight privacy
information](https://www.apple.com/legal/privacy/data/en/test-flight/).

This file is the current privacy policy; a public GitHub copy can host it.
Sensitive privacy concerns follow the confidential reporting route in
[SECURITY.md](SECURITY.md). Before distribution outside the private testing
channel, the maintainer must configure and monitor that route. No public
contact or completed legal review is claimed here.
