# Privacy

Last updated: 2026-08-24

Flowmo does not currently operate a server and contains no third-party
analytics, advertising, or crash-reporting SDK. Flowmo itself does not transmit
session data.

## Data kept on the device

Flowmo stores the current session, intentions, parked thoughts, recall text,
completed-session history, cue preference, learned break ratio, and selected
Focus Guard application identifiers. The Mac store is normally
`~/.flowmo/world.json`; `FLOWMO_HOME` is a development override. The iPhone app
and widget use the private `group.app.flowmo.phone` App Group container and do
not share a session with the Mac.

On Mac, Focus Guard observes local application activation only to hide apps the
user selected during Focus. It does not use Accessibility control, terminate
processes, or send application activity anywhere. Flowmo may also ask the
operating system for local-notification permission and play system sounds.

The local JSON file is internal storage, not a supported write API. Automation
should use supported CLI commands.

The iPhone app and widget bundle an Apple privacy manifest that declares no
tracking and no collected data. It declares required-reason code `C617.1`
because Flowmo inspects the size and type of files inside its own app and App
Group containers to read the local store safely. That metadata is not sent off
the device.

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
until **Delete All Data**. This foundation is not present in the iPhone App
Group store.

## Diagnostics and exports

Flowmo records privacy-safe issue codes in Apple's local unified logging system.
It does not log intentions, parked thoughts, recall text, selected application
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
quarantine and crash-write recovery artifacts, including the separate local
evidence store and its owned recovery artifacts. Cleanup is non-recursive; if
an artifact cannot be removed safely, Flowmo reports that deletion is incomplete
instead of claiming success.

## Apple beta services

An external TestFlight beta is not active. If it is enabled, Apple automatically
collects TestFlight crash logs and usage information and shares eligible reports
with the developer; testers cannot opt out of that TestFlight collection. This
is separate from Flowmo's own code. See [Apple's TestFlight privacy
information](https://www.apple.com/legal/privacy/data/en/test-flight/).

A public privacy-policy URL and a working privacy contact must be added before
external beta distribution. This repository file is the current policy source,
not yet a hosted policy or legal review.
