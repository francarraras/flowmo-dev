# Flowmo

Stop counting down. Start flowing up.

A Flowmodoro. You work until you stop. Rest is earned from how long you focused. One charcoal window. One circle that does not move.

The name and tagline are working placeholders. Branding, marketing, and
commercial decisions are not current product work.

**Behavior:** [`docs/PROJECT.md`](docs/PROJECT.md)
**Look:** [`docs/visual.md`](docs/visual.md)

## Open the window

```bash
cd ~/dev/flowmo
swift run flowmo
```

Leave that running. That is the app.

## Drive it from the terminal

Open a second terminal in the same folder. Paste one line at a time. Watch the window, not the text that prints.

```bash
cd ~/dev/flowmo

swift run flowmo start "try the loop"    # Prime
swift run flowmo skip                    # Focus
swift run flowmo capture "parked line"
swift run flowmo stop                    # Break
swift run flowmo skip                    # Reflection
swift run flowmo skip                    # Close
swift run flowmo skip                    # Idle
swift run flowmo status
```

In the app, Prime offers **Focus now**, Break offers **Continue**, and Reflection
offers **Skip**. The CLI keeps the stable `skip` verb for all three timed beats.

What should happen:

- After Start, the circle stays put. Start is gone.
- Focus counts up. Gold is rest you are earning.
- Break is gold.
- Close shows **Focused** and **Rested**. After the last Skip, Idle is empty again.
- **History** still has the parked line. Tap a card to open it.

Same session as the window. The current local store is `~/.flowmo/world.json`,
but it is internal storage—not a supported write API. Automation should use the
CLI verbs against that same store; direct `world.json` writes are unsupported.
The Mac app keeps privacy-bounded Focus Guard instrumentation separately in
`~/.flowmo/evidence.json`; that file is also internal storage, not an automation
contract. In the WP3 implementation, **Stay focused** may reactivate the exact
prior unguarded process instance; a matching activation notification within
one second is required before that attempt counts as confirmed.

```bash
swift run flowmo live      # ticking view of that session
swift run flowmo check     # core proofs
swift run flowmo-wp3-gate --help  # optional local WP3 field-audit evaluator
```

## Script integration

`status --json` is the read contract for automation. Its response has
`schemaVersion: 1`, a `generatedAt` timestamp, and a `status` object. Supported
action commands (`start`, `stop`, `skip`, `continue`, `restart`, `cancel`,
`capture`, and `recall`) accept `--json` in any position after the command and
return a structured success or error envelope. The action envelope deliberately
does not echo intentions, captures, or recall text; call `status --json` only
when that text is needed.

`pause` and `resume` are not CLI flow controls. Recovery uses `continue` or
`restart` after quit/sleep. There is no Focus pause command. Other action
commands return `recovery_paused` until recovery is resolved.

iPhone is a native app (`Apps/FlowmoPhone.xcodeproj`) that synchronizes the loop
with the entitled Mac app through the user's private CloudKit database. Both
keep working from local replicas when CloudKit is unavailable; simultaneous
offline starts require an explicit choose-one decision. The old tree in
`~/Flowmo` is reference only.

## Verify a candidate

```bash
swift format lint --strict --recursive Package.swift Sources Tests Apps
swift test -Xswiftc -warnings-as-errors
swift run -Xswiftc -warnings-as-errors flowmo check
swift build -c release -Xswiftc -warnings-as-errors
```

The Mac and iPhone apps also provide redacted diagnostic export, full-data
export, invalid-store recovery, and confirmed deletion while Idle. The Mac Data
view separately exports its best-effort aggregate Focus Guard counts; nothing
is uploaded automatically, and **Delete All Data** removes them. See the
[`release procedure`](docs/release.md), [`privacy policy`](PRIVACY.md), and
[`security policy`](SECURITY.md) before sharing a build.
