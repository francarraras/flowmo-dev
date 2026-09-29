# Developing Flowmo

## Start from a clean clone

The source, assets, shared Xcode schemes, and instructions are in Git. Builds
require no Codex desktop state, plugin, or editor integration. Use full Xcode
26.3 or newer with its Swift 6 toolchain; Command Line Tools alone are not the
supported setup. The Liquid Glass source needs the macOS/iOS 26 SDK even though
the apps retain macOS 14+ and iOS 17+ runtime support. CI selects Xcode 26.3.

```sh
git clone --branch codex/weekend-readiness https://github.com/francarraras/flowmo-dev.git
cd flowmo-dev
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift --version
git status --short
```

Adjust `DEVELOPER_DIR` to the installed full Xcode bundle. Complete Xcode's
first-launch component setup and install a compatible iOS simulator runtime
for interactive phone checks. `codex/weekend-readiness` contains the build 8
candidate; `main` still carries older source at this handoff. Continue from the
candidate branch until it is reviewed and merged.

## Run the native surfaces

Launch the Mac window against a disposable session store:

```sh
flowmo_test_root="$(mktemp -d "${TMPDIR:-/tmp}/flowmo-development.XXXXXX")"
FLOWMO_HOME="$flowmo_test_root" swift run flowmo
```

Keep that same override for every launch in the test, including recovery
relaunches. To use the living terminal beside this window, open a second
terminal, set `FLOWMO_HOME` to the same temporary directory, and run
`swift run flowmo live`. Quit the test processes before removing their
temporary store.

For an installable Mac bundle and terminal installation, see
[source builds](installation.md#build-from-source). The Xcode Mac host is the
app; the SwiftPM `flowmo` executable also provides the CLI.

| iPhone scheme | Use and storage |
| --- | --- |
| `FlowmoPhoneLocal` | Free Personal Team or simulator testing; `FlowmoLocal.app` (`app.flowmo.phone.local`), independent local container and Focus Live Activity. No CloudKit or Home Screen widget. |
| `FlowmoPhone` | Entitled App Group/CloudKit app (`app.flowmo.phone`) and read-only Home Screen widget. Simulator compilation does not establish physical-device provisioning or cloud transport. |

Open `Apps/FlowmoPhone.xcodeproj` in Xcode to run the chosen scheme on a
disposable simulator. For a physical phone, follow
[personal-device installation](installation.md#iphone-with-xcode) and
[build variants](iphone.md#build-variants). Switching schemes does not migrate
sessions. An ordinary local Mac/CLI build does not synchronize with either
phone app.

## Checks

```sh
swift format lint --strict --recursive Package.swift Sources Tests Apps
swift test -Xswiftc -warnings-as-errors
swift run -Xswiftc -warnings-as-errors flowmo check
swift build -c release -Xswiftc -warnings-as-errors
```

The complete CI recipe is [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).
It also verifies CLI JSON/privacy behavior, Release builds and Debug static
analysis for the Mac, entitled phone/widget, and local phone/Live Activity,
bundled privacy manifests and entitlements, and a separate Intel CLI job.
Use the workflow's exact commands when reproducing a failed gate; a local
Apple-silicon run does not replace the Intel runner. GitHub CI must pass for
the exact pushed revision.

For behavior changes, follow [the repo rules](../AGENTS.md), reproduce using
synthetic data, and run the feature's proof from the
[feature map](feature-map.md). Automated checks do not cover every native UI
or device path. Packaging with `Scripts/family-preview` is a release action,
not an ordinary CI check; use [the release procedure](release.md).

## Automation

Use the supported CLI instead of editing internal JSON directly. Run
`swift run flowmo --help` for verbs and `--json` for the versioned machine
contract. `flowmo status --json` includes session text; action responses do
not echo it. Keep exports and private session text out of prompts, issues,
logs, screenshots, and commits. See [CLI behavior](PROJECT.md#cli-and-scripts).

## Local state when changing editors or machines

| State | Location and handoff treatment |
| --- | --- |
| Mac app and terminal session store | `~/.flowmo/world.json` by default; `FLOWMO_HOME` overrides its directory. App and CLI share one live session per store. Keep this private state outside Git. |
| Flowmo Local phone store | `Application Support/flowmo/world.json` inside `app.flowmo.phone.local`'s sandbox. It stays independent of the Mac and entitled phone stores. |
| Entitled phone/widget store | `flowmo/world.json` inside App Group `group.app.flowmo.phone`; private CloudKit sync requires eligible entitled builds. |
| Presentation/tutorial preferences | Platform `UserDefaults`; `FLOWMO_HOME` does not isolate these. Use a disposable OS account or engineering app identity for preference-sensitive Mac UI checks. |
| Generated output and machine configuration | Ignored `.build/`, `.swiftpm/`, `dist/`, and Xcode user data. Rebuild caches; retain any needed release archives, manifests, and checksums separately before deleting the old checkout. |

Changing editors on the same Mac does not move or delete session data. On a
new machine, use the app's export for private safekeeping; an editor handoff
is not a session-import mechanism. Keep signing accounts, provisioning
profiles, simulator state, and private exports local. Phone profile renewal
must reinstall over the same app; deleting the app removes its container.

## Source and release state at handoff — 2026-09-29

Mac and CLI source metadata is **1.0 build 8**; phone and extension targets
remain **1.0 build 7**. The published downloads are still
[build 6](https://github.com/francarraras/flowmo-dev/releases/tag/v1.0.0-preview.6).
The [preview ledger](PREVIEW_RELEASES.tsv) records build 6 as `distributed`
and builds 7/8 as `candidate-generated`. The
[changelog](../CHANGELOG.md) describes source changes; the
[build 8 validation record](release.md#build-8-visual-follow-up--2026-09-09)
identifies the packaged source and observed checks. Its results belong to
that candidate, not every later commit.

Remaining release proof includes full VoiceOver, real Focus Guard behavior,
fresh-recipient Gatekeeper opening, installed CLI window/artwork, physical-phone
reminders/activity/accessibility and expired-profile renewal, and cross-display
Scene movement. Consult [the release record and manual gates](release.md) for
the exact evidence and boundaries. Build 6's approved deferrals do not approve
distribution of builds 7/8. Do not reuse reserved build numbers or overwrite
earlier preview artifacts.

## Architecture and behavior

- [Domain vocabulary](../CONTEXT.md)
- [Product behavior](PROJECT.md)
- [Architecture](architecture.md)
- [Feature and test map](feature-map.md)
- [Visual design](visual.md)
- [Focus Guard](focus-guard.md)
- [Terminal view](live.md)
- [Release procedure and evidence](release.md)

Start with the repo rules and product behavior, then use the feature map to
find the owning module and regression proof. `FlowmoCore` owns session rules
and durable World actions; platform controllers remain adapters. Roadmap
items in [v2](v2.md) are not shipped behavior. The frozen `~/Flowmo` tree is
visual/formula reference only and is not needed to build this repository.
