# Release procedure

Flowmo 1.0 build 6 is published as a GitHub prerelease.
The repository owner is recorded as Fran Carrara. Flowmo is the working name
until the owner reopens branding. An owner-authorized Mac-only friends-and-family
preview may be shared under the explicit limitations below.

## GitHub-first distribution

The near-term distribution target is a GitHub release with a Mac app and a
separate Mac terminal executable. App Store publication is not a prerequisite
or part of this candidate. [Build 6 preview downloads](https://github.com/francarraras/flowmo-dev/releases/tag/v1.0.0-preview.6)
are available. No donation address or iPhone beta link is configured; do not add
invented destinations.

On 2026-09-05 the owner ruled out paying for Apple Developer Program membership.
The chosen path is open source plus local-only Mac/terminal downloads, with
explicit ad-hoc signing and installation limitations, and a free Personal Team
iPhone build for personal use. Developer ID, notarization, TestFlight, and
entitled iCloud/Home Screen widget delivery are outside this release scope.
Membership is not a pending purchase or a prerequisite for publishing the source. Manual
quality checks and owner review still apply to every distributed build.

- **Mac:** the current scripts produce ad-hoc local-only candidates. Source
  builds and clearly labeled non-notarized archives are the chosen GitHub path;
  first opening a downloaded archive may require Apple's per-app Open Anyway
  flow. Never describe these as Apple-verified or require global security
  changes. Developer ID signing/notarization remains an optional future route
  if the owner changes the membership decision. See [Apple's opening guidance](https://support.apple.com/102445).
- **Terminal:** distribute a separate universal executable and installer, with
  a checksum, matching app version/build, and installation, upgrade, and removal
  instructions. The Xcode Mac app host does not serve CLI commands.
- **iPhone:** use the `FlowmoPhoneLocal` scheme for free personal-device builds;
  see [Free personal testing](#free-personal-testing). A GitHub IPA is not a
  general installation route. The remaining routes here are reference only,
  outside the chosen no-membership scope: registered-device
  Ad Hoc testing needs a paid team and device registration (up to 100 iPhones
  per membership year). TestFlight is an optional beta channel without a public
  App Store listing, but still uses Apple infrastructure, first external-build
  review, and 90-day build expiry. Regional alternative distribution has separate
  eligibility and review requirements; it is not a worldwide GitHub-download
  shortcut. See [devices](https://developer.apple.com/help/account/devices/devices-overview),
  [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/),
  and [regional alternatives](https://developer.apple.com/documentation/marketplacekit/participating-in-alternative-distribution-for-specific-regions).

The candidate includes MIT in `LICENSE`, using the confirmed copyright owner.
Review and include that exact license with the public candidate. The existing
GitHub bug form can handle ordinary public reports once Issues are available;
a separate support email is not required. Before public distribution, configure
and monitor GitHub private vulnerability reporting or put a real confidential
contact in `SECURITY.md`, and make the privacy policy available to recipients.
Do not claim a private-report button is enabled without checking it. A donation
can be a README/About link and `.github/FUNDING.yml` once the owner supplies a destination;
no payment SDK or account system is needed. See [GitHub licensing](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
and [funding links](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository).

### Build 6 preview decision

On 2026-09-07 the owner explicitly approved public source/history and build 6
Mac/terminal distribution as a preview, with these checks deferred: real macOS
Focus Guard interception/return; full VoiceOver and large-text touch navigation;
fresh-recipient Gatekeeper opening; installed terminal no-argument GUI artwork
with isolated preferences; full physical-phone reminder/accessibility coverage
and later provisioning renewal. These are unverified paths, not confirmed
failures. The public release notes carry these limits. This decision applies
only to build 6 and does not waive future release checks.

Both archives retain source revision `be97de9020980150a6efbfa2dad6f6aeda3ed12e`;
release tag `v1.0.0-preview.6` points to its receipt revision
`d824c4dcfd821d20381fcce0f9769b64d2a76fd0`. GitHub confidential reporting was
enabled and verified before the downloads were published.

### Build 7 local candidate — 2026-09-08

Build 7 packages source `e47264ad30d9bd20fa4e0685147a40afe97963ab`,
including the Canvas tutorial illustrations. The owner requested packaging,
installation, and completion of the deferred checks. This is a local candidate;
build 6 remains the public release, and its preview deferrals do not approve
public distribution of build 7.

Completed:

- Strict format, 287 tests, core proofs, release builds, and the Mac preview
  script's build/analysis, privacy, signature, architecture, extraction, and
  checksum gates passed.
- Both universal archives were generated without overwriting prior releases.
  Packaging now rejects missing tutorial images; the Mac package also compares
  each image byte-for-byte against the committed source.
- Build 7 Mac app installed in `/Applications/Flowmo.app`; the prior installed
  app was archived locally for rollback. App data was not moved or deleted.
- Build 7 CLI installed in the owner's local bin directory. A separate disposable
  build 6 → 7 installation preserved the synthetic session store byte-for-byte.
- Free-personal iPhone simulator static analysis passed.
- Personal Team Release build succeeded and installed over the existing local
  app on the connected iPhone 15 Pro Max. Device app metadata confirmed build 7.
  All three tutorial PNGs matched source in both the installed Mac app and the
  signed phone build. No owner session data was inspected.

Still unverified:

- Real macOS Focus Guard interception, Stay focused return, and fail-open paths.
- Full VoiceOver and largest-text reachability, including tutorial page controls.
- Fresh-recipient Gatekeeper opening. The automated rejection is expected for
  ad-hoc signing and is not evidence that the recipient Open Anyway path works.
- Installed terminal no-argument GUI artwork with isolated preferences.
- Physical-phone background reminders, activity edge cases, accessibility, and
  history preservation through an expired-profile renewal. Reinstalling today
  establishes installation success, not these behavioral checks.

The desktop-control service timed out during this attempt. Unlocked Mac and
phone access was requested for interactive verification. Do not mark these
paths passed until directly observed. See the build 7 manifests in local `dist/`
and its candidate-generated receipt in `PREVIEW_RELEASES.tsv`.

### Build 7 interactive follow-up — 2026-09-08

After the owner unlocked the devices, the installed Mac app was launched with
an isolated `FLOWMO_HOME` and synthetic content. All three tutorial pages were
visible; Set intention returned to empty Idle. Prepare advanced to open-ended
Focus; Stop produced 44 seconds of earned Break from about 3.7 minutes of Focus.
Reflection and Close Beat were reachable. The forced first-use launch argument
kept tutorial version zero visible to that process, so the Mac run is not proof
of persisted tutorial dismissal. A separate preference directory was requested
through the process environment, but preference isolation was not established.

On the disposable iPhone 17 simulator (iOS 26.5), build 7 was tested with
`accessibility-extra-extra-extra-large` content size:

- Tutorial Skip and Continue stayed visible; page navigation and body scrolling
  were observed. Full end-to-end reading of every scrolled paragraph was not
  established. Set intention returned to Idle without starting a session.
- Prepare, Focus now, Park thought, End focus, earned Break, Reflection, and
  Close Beat were operated through the UI. Focus time continued during capture.
- A completed next step returned to editable Idle. Relaunch stayed at Idle
  instead of replaying the tutorial; Data → How it works replayed it explicitly.
- One typed next step appeared to lose its final character at completion. A
  repeat with a distinctive five-digit ending preserved the exact visible field
  value through Close Beat and Idle. Input automation/autocorrection also changed
  typed words. The truncation observation is unresolved, not a confirmed defect
  or a demonstrated fix; retest by direct typing before declaring this path fully
  verified.

Focus Guard was configured with Calculator in the disposable Mac store, but
normal foreground activation and interception were not established through the
computer-control tool. No interception pass or Guard defect is claimed. The
installed no-argument CLI process launched, but the computer-control tool rejected
its standalone executable as an app target; its visible artwork remains unverified.
Full VoiceOver navigation and fresh-recipient Gatekeeper opening remain open.
The owner was asked to observe the physical-iPhone Prepare background reminder;
no response had arrived when these results were recorded.

### Unreleased Horizon visual smoke — 2026-09-09

Source `8551f36` was exercised on macOS 26.6.2 with Xcode 26.6, and a fresh
iPhone 17 simulator running iOS 26.5. The Mac engineering app used a separate
bundle identity and disposable session store; the phone used `FlowmoPhoneLocal`
on the disposable simulator. These were test builds, not preview archives.

Observed through the native UI:

- Mac Classic Idle and Prime fit the fixed frame; the empty and single-entry
  Guard cards kept Add app and Remove visible. Adding and removing an entry
  worked. The primary action stayed ivory and quiet controls/chrome rendered
  with the new material treatment.
- Prime's Focus scene opened the live rendered Horizon with a count-up and
  earned-rest mark. Back to window restored Classic without stopping Focus.
  Switching to Mini, entering Scene, and returning restored Mini with the clock
  continuing. The size menu contained only Classic and Mini.
- Mac quit/relaunch recovery, once launch isolation was made persistent, stayed
  frozen at 00:55 until Continue. Stop, Break, Reflect, Reflection Skip, Close
  Beat, and Done returned to Idle. An earlier relaunch lost the process-only
  store override; exclude that attempt from isolated recovery evidence. The
  corrected disposable app wrapper supplied the override on every launch.
- Phone Prime entered the live Horizon. Capture kept counting, and Discard/Park
  remained visible above the software keyboard at ordinary text size. Park
  saved a synthetic thought and updated the parked count.
- The simulator's Settings showed maximum accessibility text size (100%) and
  Reduce Motion enabled. Focus actions stacked. With the software keyboard,
  enlarged capture scrolled to reveal Discard and Park; Park saved successfully.
- Background/foreground retained the phone Focus, and the Home Screen showed
  its Dynamic Island count-up. Termination/relaunch showed compact Recovery
  Pause frozen at 05:35; only Continue resumed it. Break, Reflection, Close Beat,
  and Done were usable at maximum text size. The synthetic next step
  `Next step 98765` was preserved exactly into editable Idle without starting.

Limitations and observations:

- Coordinate dragging repeatedly failed in the desktop-control service with
  `noWindowsAvailable`. Scene dragging, edge resizing, and movement between
  displays are not verified by this pass.
- Maximum-size Reflection truncates its empty placeholder visually; the full
  prompt remains in the accessibility tree. Mini Close Beat also truncates its
  compact earned-break label. These are observed presentation limitations, not
  fixes made in this pass.
- Reduce Motion was enabled on the simulator and its loop remained usable;
  this is not frame-by-frame proof of ambient animation suppression. Mac Reduce
  Motion, three-row Guard overflow, real Guard interception, full VoiceOver,
  and physical-device checks remain unverified.
- This pass does not replace exact-archive/manual distribution checks or owner
  approval. No preview was packaged or distributed.

### Build 8 visual follow-up — 2026-09-09

The two presentation limitations above were fixed and retested on the same
Mac and disposable iPhone 17 simulator. Mini Close Beat now stacks the earned
label and duration; both were fully visible with a next step and parked thought
also present. The iPhone Reflection prompt wrapped completely at maximum
accessibility text size with Reduce Motion enabled. Return still completed
Reflection and preserved the exact synthetic next step `Return proof 24680`.

The desktop-control service accepted native dragging on this follow-up. Scene
was dragged from its empty canvas and resized from bottom-right and top-left;
the latter reached the documented 720×480 minimum with both actions visible.
Focus kept counting and Back to window returned to Classic. Cross-display
dragging was not tested.

Mac Reduce Motion was confirmed off, enabled for Scene return/re-entry, and
restored to off after the check. Scene and its count-up remained usable.
Two additional shader-input regression checks cover advancing wall time with
ambient motion disabled and frozen recovery with ambient motion requested.
They establish stable rendering inputs, not a measured frame-rate or energy
profile. No Horizon tuning or Liquid Glass behavior was reverted.

This is a build 8 candidate preparation, not a distribution decision. The
earlier unrelated manual gaps (including full VoiceOver, real Guard behavior,
fresh-recipient opening, physical-phone checks, and cross-display movement)
remain open. The exact archive's generated manifest and receipt identify its
source and automated packaging evidence.

### Terminal candidate packaging

After the code and version metadata are reviewed, run from a clean committed
checkout:

```bash
./Scripts/package-cli
```

This builds the SwiftPM `flowmo` product for arm64 and x86_64, combines the
executables, ad-hoc signs with Hardened Runtime, and creates a versioned `.tar.gz`,
SHA-256 file, and manifest in ignored `dist/`. The archive includes an installer,
the adjacent `flowmo_FlowmoLook.bundle` artwork, complete payload checksums,
license, provenance, third-party notices, privacy policy, and readme. Packaging
checks that both architectures produce identical resources, extracts the exact
archive, and verifies its architectures, signature, payload checksums, version,
isolated idle JSON response, and installed command. Separately smoke the installed
no-argument window and Focus artwork after the build directory is gone; a version
or status command does not load that artwork. Packaging refuses existing output
names, checks that the embedded CLI version/build matches the Mac project, and never uploads,
pushes, tags, or changes the preview ledger. A clean package is still a candidate
and requires the complete gates and owner review before distribution.

`--allow-dirty` builds an engineering archive visibly marked **DIRTY / DO NOT
DISTRIBUTE**; use it only to test packaging before the candidate is committed.
Both modes build an isolated source snapshot; dirty mode fingerprints the
source around the copy and stops if concurrent edits change it. `--output-dir
PATH` changes the output location. Neither mode applies Developer
ID signing or notarization. GitHub downloads must disclose these limitations.
An Apple-trusted download would require a separately reviewed signed/notarized
packaging route that includes the CLI executable; it is outside the chosen scope.

Verify a supplied archive with `shasum -a 256 -c ARCHIVE.tar.gz.sha256` using the
actual checksum filename, then extract it. From the extracted folder, run
`./install.sh`; installation defaults to `~/.local/bin` and prints the PATH
instruction without editing shell configuration. The installer checks the
complete binary/artwork inventory and checksums and preserves extended attributes,
including quarantine. It places each complete payload beneath
`PREFIX/libexec/flowmo/<content-digest>.<installation-id>` and makes
`PREFIX/bin/flowmo` a small launcher that starts its executable. The artwork
bundle must stay beside the actual executable, including when installing a local
build with `--binary`; use the SwiftPM output path shown in the README.
After quitting running Flowmo instances, `./install.sh --replace` explicitly
upgrades an existing regular executable or managed installation; `--upgrade` is
an alias. It switches the launcher atomically only after checking the new payload,
retains previous payloads, and rejects unrelated symlinks. `--prefix PATH` chooses
another prefix. Removing `PREFIX/bin/flowmo` uninstalls the command. After quitting,
the installer-owned `PREFIX/libexec/flowmo` directory may also be removed to reclaim
binaries and artwork. Both removals preserve sessions stored separately.
The README also documents installation directly from a permitted source build.

## Free personal testing

An Apple Account with Xcode's Personal Team supports personal-device testing
with supported capabilities. Provisioning profiles expire after seven days;
the app must be rebuilt and reinstalled afterward. Apple also limits a Personal
Team to three devices and three installed apps per device. This is personal
testing, not a public iPhone distribution channel. See [Apple's current limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

Use the separate `FlowmoPhoneLocal` scheme in `Apps/FlowmoPhone.xcodeproj`:

1. Connect and unlock the iPhone, and trust this Mac when prompted.
2. Sign into the owner's Apple Account in Xcode, then select its Personal Team
   under both **FlowmoPhoneLocal** and **FlowmoFocusActivity** targets' Signing &
   Capabilities. Account login, agreements, and device trust remain actions for
   the owner.
3. Select that connected iPhone as the run destination and Run. If necessary,
   follow Xcode's on-device Developer Mode and provisioning instructions.
4. If iOS reports an untrusted developer after installation, open **Settings →
   General → VPN & Device Management → Developer App** on the iPhone and trust
   the owner's Apple Account entry, then reopen Flowmo Local. This is separate
   from trusting the connected Mac and enabling Developer Mode.

The local target uses its own bundle identifier and app-container store. It
does not request App Group, iCloud, or push entitlements. It embeds the
`FlowmoFocusActivity` extension for its read-only Focus Live Activity, but no
Home Screen widget. Apple's [Food Truck sample](https://github.com/apple/sample-food-truck#configure-the-sample-code-project)
documents Personal Team signing for an app and widget extension; verify actual
signing and installation for each candidate. The focus loop, recovery,
exports, and local notification reminders remain available. It does not read,
migrate, or sync the entitled phone store.
Reinstall over the existing local app to refresh provisioning; deleting the app
also deletes its app-container data, so export first if preserving data matters.

The existing `FlowmoPhone` scheme remains the entitled App Group/CloudKit/widget
build for eligible contributors. A missing App Group in that build remains an
unavailable state, never a silent switch into the local store.

Do not describe an ad-hoc Mac build as Developer ID signed, notarized, or
Apple-reviewed, or describe free personal provisioning as public iPhone delivery.

## Informal Mac friends-and-family preview

Under the chosen no-membership path, the owner may share a narrowly scoped
Mac engineering preview with people who know and trust the sender. This path is
not available for the iPhone app or widget.

The preview script explicitly removes the Mac CloudKit entitlements so the app
can remain ad-hoc signed. That package is local-only and is not evidence for
cross-device sync. Never describe it as an iCloud-enabled build.

- Build a fresh Release app from the candidate worktree and verify the signature,
  architectures, version, and minimum macOS version.
- Package the app with `docs/FRIENDS_AND_FAMILY.txt`, `PRIVACY.md`, `LICENSE`,
  `PROVENANCE.md`, and `THIRD_PARTY_NOTICES.md`.
- Generate a SHA-256 checksum for the final ZIP and send the checksum separately
  from the archive when practical.
- State plainly that the build is ad-hoc signed, not Developer ID signed, and not
  notarized. macOS Gatekeeper is expected to reject ordinary first launch.
- Instruct recipients to use Apple's per-app Privacy & Security > Open Anyway
  flow only if they received the expected archive directly. Never ask them to
  disable Gatekeeper globally or run a quarantine-removal command.
- If macOS reports that the app will damage the computer or that it is damaged,
  the recipient must stop rather than override the warning.
- Treat every replacement ZIP as a new build: rerun all release gates, increment
  the build number, archive its checksum, and keep the preceding archive for
  rollback.

This exception makes informal testing possible; it does not satisfy the signed
distribution requirements later in this document.

### One-command preview candidate

After a change is finished:

1. Add or update the relevant proof, move tester-visible notes from Unreleased
   into a `VERSION (BUILD)` changelog section, increment both Mac
   `CURRENT_PROJECT_VERSION` settings, synchronize the CLI’s embedded
   `Sources/FlowmoApp/Info.plist` version/build, and synchronize
   `docs/FRIENDS_AND_FAMILY.txt`.
2. Review and commit the exact candidate. Packaging a dirty worktree is not a
   release record.
3. Confirm the version/build is new in `docs/PREVIEW_RELEASES.tsv`, then run:

   ```bash
   ./Scripts/family-preview
   ```

The command runs the automated release gates below in fresh Derived Data,
creates the Mac ZIP without overwriting an earlier build, generates its SHA-256
file and release manifest, extracts the exact ZIP, and re-verifies its contents,
metadata, architectures, signature, Hardened Runtime, and entitlements. It does
not push, tag, notarize, upload, or send anything. After a clean candidate
succeeds, it appends a `candidate-generated` receipt to
`docs/PREVIEW_RELEASES.tsv`, immediately reserving that version/build even if
the output archive is later moved.

`--allow-dirty` exists only for testing the automation itself. Its filename,
package, tester guide, and manifest are marked **DIRTY / DO NOT DISTRIBUTE**.
That output must never be sent to a tester.

Before sharing the generated candidate, commit its appended ledger receipt and
complete every manual gate listed in its manifest and steps 7–9 below. After
owner review, change the receipt status to `distributed` or `withdrawn` and
commit that decision. Keep the previous ZIP and checksum available for rollback.
The ledger reserves old build numbers even if `dist/` is cleared or an archive
is moved elsewhere.

## Required verification

`./Scripts/family-preview` runs the shared gates, packages the Mac app, and
checks the entitled phone/widget simulator build. Run the Flowmo Local and
physical-device checks below separately; the script does not cover them.

GitHub CI also builds and runs the Release CLI and core proofs on a standard
Intel Mac runner, including isolated JSON and privacy checks. This verifies
native Intel execution of the candidate source; exact universal archive
verification remains part of local packaging. Keep the reported CI operating
system and toolchain versions with each run's result.

From a clean checkout of the candidate revision:

1. Run `swift format lint --strict --recursive Package.swift Sources Tests Apps`.
2. Run `swift test -Xswiftc -warnings-as-errors`.
3. Run `swift run -Xswiftc -warnings-as-errors flowmo check` and
   `swift build -c release -Xswiftc -warnings-as-errors`.
4. Build and analyze the Mac app:

   ```bash
   xcodebuild -project Apps/Flowmo.xcodeproj -scheme Flowmo -configuration Release -sdk macosx -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
   xcodebuild -project Apps/Flowmo.xcodeproj -scheme Flowmo -configuration Debug -sdk macosx -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES analyze
   ```

   An entitled candidate instead requires normal Apple provisioning and must
   not use the empty-entitlements or ad-hoc identity overrides.

5. Build and analyze the chosen local iPhone target in the simulator:

   ```bash
   xcodebuild -project Apps/FlowmoPhone.xcodeproj -scheme FlowmoPhoneLocal -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
   xcodebuild -project Apps/FlowmoPhone.xcodeproj -scheme FlowmoPhoneLocal -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES analyze
   ```

   Inspect the built `FlowmoLocal.app`: no App Group, iCloud, or push
   entitlements and no remote-notification background mode. Confirm
   `NSSupportsLiveActivities` is enabled and only `FlowmoFocusActivity.appex`
   is embedded, with bundle `app.flowmo.phone.local.focus-activity`, no restricted
   capabilities, and no Home Screen widget configuration. The entitled phone
   build must not embed this local extension.
   Verify its independent store and local deletion without migration or sync.
   Keep the existing entitled phone/widget build as regression proof when shared
   phone code or project configuration changes; it is outside the chosen delivery scope:

   ```bash
   xcodebuild -project Apps/FlowmoPhone.xcodeproj -scheme FlowmoPhone -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
   xcodebuild -project Apps/FlowmoPhone.xcodeproj -scheme FlowmoPhone -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES analyze
   ```

6. Smoke-test the Mac window and `swift run flowmo status --json` against an
   isolated `FLOWMO_HOME`.
7. Launch and smoke-test on the intended latest macOS version and the latest-iOS
   iPhone 15, 16, and 17 simulators. Exercise each product phase, quit/sleep
   recovery, invalid-store repair, redacted diagnostics, full export, confirmed
   deletion, Focus Guard failure, and phone unavailable state. Widget glance
   checks apply only to the entitled target.
   Check first-launch guidance once, tutorial replay, and notification permission
   after its explanation. Install the CLI into a temporary prefix; verify help
   does not mutate a session, unknown commands fail, and q/Escape/Ctrl-C leave
   the living view immediately with the terminal restored. Explicitly upgrade
   that installation and verify its local session data is preserved.
   For WP3, confirm one real-app **Stay focused** path returns to the exact prior
   app, and confirm an unavailable prior app preserves the safe hidden fallback.
   Confirm a second Mac process cannot mutate the first process's lifecycle and
   an immediate CLI Continue survives crash recovery without losing frozen
   time. Confirm Focus always counts up with no pause or progress ring.
   From Prime, use a harmless app/window with synthetic content and verify
   ordinary **Focus now** enters Focus and returns to that exact already-running
   app when eligible, while a guarded target is not reopened. Keep app and
   document identity out of screenshots, notes, and bug reports. Verify
   **Focus scene** enters the same Focus from Prime. During an active Focus,
   enter from Classic's named **Focus scene** and Mini's named **Scene**.
   After **Back to window**, re-enter through the named action and confirm the
   chrome size menu contains only Classic and Mini. Confirm
   Scene remains movable and resizable and returns to the exact prior
   Classic/Mini presentation without changing the clock.
   On iPhone, confirm active unpaused Focus fills the frame with Distant
   Horizon in the supported portrait orientation, keeps Park thought and End
   focus reachable, and retains the timestamp clock across background/foreground.
   Confirm rotation keeps the app in portrait; landscape is not supported.
   Check Dynamic Type and Reduce Motion, then terminate during Focus and
   confirm relaunch shows the compact Recovery Pause instead of resuming.
   Complete a session
   with a synthetic next step and confirm **Done** carries only that exact step
   into editable Idle without starting; repeat with a blank step. Stale
   competing completion remains a controller regression proof rather than a
   live smoke setup.
   For Flowmo Local, also follow [Free personal testing](#free-personal-testing)
   on the owner's trusted iPhone with their Personal Team; the simulator's
   ad-hoc signing overrides are not device provisioning instructions. Record
   actual installation and launch separately from simulator success. With
   synthetic data, verify tutorial persistence/replay and explicit notification
   permission, Prime's background reminder, both Break and Reflection reminders
   during one uninterrupted background period, and force-quit recovery with
   Continue and Restart. Profile renewal must later be checked by reinstalling
   over the same app and confirming its history remains; do not claim it from
   an initial install.
   For the Focus Live Activity, enter Focus while foreground, go Home, and
   verify compact/expanded Island and Lock Screen clocks without written text.
   Tap to return without changing the session. Stop and confirm removal; force
   quit separately and verify relaunch ends stale activity without resuming.
   Let Prime expire in the background: notification first, Live Activity only
   after opening into Focus. Check disabled/dismissed activities, competing
   Island presentations, and a phone without Dynamic Island. Neither a working
   Prime notification nor ordinary Home Screen backgrounding proves this path.
   For an entitled sync candidate, also test two signed-in devices: make an
   offline change on each, confirm distinct history unions, confirm simultaneous
   live starts block for a choose-one decision, verify account switching never
   uploads the prior account's pending data, and verify offline Delete All stays
   visibly incomplete until CloudKit confirms deletion.
8. Review `CHANGELOG.md`, `PRIVACY.md`, `SECURITY.md`, `PROVENANCE.md`, and
   `THIRD_PARTY_NOTICES.md`. Validate the local phone's
   `Apps/FlowmoPhoneLocal/PrivacyInfo.xcprivacy`, confirm it is bundled and declares
   no collected data or tracking. Also verify
   `Apps/FlowmoFocusActivity/PrivacyInfo.xcprivacy` in the extension, with empty
   collected-data and accessed-API lists and no tracking. For the Mac and entitled
   phone/widget builds, validate their shared `Apps/PrivacyInfo.xcprivacy` and
   bundled copies. Archive the exact test results with the release revision.
9. Record the candidate commit, Xcode version, macOS version, simulator runtime,
   and device models. Confirm `git diff --check` passes and the committed
   candidate checkout is clean.

The local Mac Release configuration enables Hardened Runtime, but the command
above still produces an ad-hoc development build. Hardened Runtime alone is not
Developer ID signing or notarization.

## Beta bug loop

1. Record the build, device/OS, surface, issue code, expected result, and the
   shortest reproducible steps. Keep intentions and full exports out of issues.
2. Reproduce against an isolated `FLOWMO_HOME` or disposable simulator. Preserve
   a corrupt store privately; share a redacted diagnostic report first.
3. Add a failing automated proof when practical, fix the underlying invariant,
   and verify both the original trigger and the legitimate behavior beside it.
4. Run the required verification above, update `CHANGELOG.md`, and prepare a
   new build number with concise retest steps for owner-reviewed distribution.
   Keep the previous signed build available for rollback.

## Before TestFlight or Apple-trusted external distribution

This section is reference for a future change of scope. These routes are
excluded by the owner's current no-paid-membership decision.

These are blocking for TestFlight, a Developer ID Mac beta, or any broader
release described as Apple-trusted. They do not block the explicitly scoped,
ad-hoc friends-and-family Mac preview above:

- Enroll the legal owner in the paid Apple Developer Program. Apple currently
  lists it as US$99/year. An Apple-trusted local-only Mac release needs Developer ID signing
  and notarization; it does not require App Group, CloudKit, or push setup.
- **For iPhone and entitled sync builds:** create the app identifiers, App
  Group, certificates, push capability, `iCloud.app.flowmo` CloudKit container,
  and provisioning profiles under that team. Promote the tested CloudKit
  development schema to production before a production-signed sync build.
- **For TestFlight only:** create the App Store Connect app record. Increase
  `CURRENT_PROJECT_VERSION` for every uploaded build and keep the phone app and
  widget versions aligned.
  Complete the required TestFlight metadata, review notes, export-compliance
  answers, privacy answers, and tester groups before inviting anyone.
- Decide the distribution paths. External TestFlight builds receive TestFlight
  App Review, expire after 90 days, and need beta description, review notes, and
  a monitored feedback email. A direct Mac beta needs Developer ID signing,
  secure timestamping, Hardened Runtime, notarization, and stapling.
- Supply an app icon/working visual identity, hosted privacy-policy URL, in-app
  privacy access, support contact, and confidential security channel.
- **For TestFlight only:** tell testers that Apple automatically collects crash
  and usage data. Use TestFlight crash reports plus Flowmo's opt-in redacted diagnostic
  export; do not add third-party analytics merely to discover bugs.
- Confirm export-compliance answers for every build. The current iPhone targets
  declare no non-exempt encryption because Flowmo ships no cryptography; review
  that declaration whenever networking or cryptographic code changes.
- Re-audit required-reason APIs and `Apps/PrivacyInfo.xcprivacy` whenever file,
  device, preferences, or third-party SDK APIs change.
- **For an App Store Connect submission:** keep privacy answers aligned with the
  manifest: private iCloud synchronization uses Other User Content and Product Interaction, linked to
  the user's iCloud identity, solely for app functionality, with no tracking.
- Confirm the copyright owner name and Git author aliases in `PROVENANCE.md`.
  Include the reviewed `LICENSE` with direct Mac and terminal distributions.
  Apple agreements and submission terms apply if TestFlight is chosen; they
  are not a requirement to publish the source repository on GitHub.
- Tag only a clean, reviewed revision. Retain the prior signed build, symbols,
  changelog, and rollback notes.

Official Apple references: [membership
comparison](https://developer.apple.com/support/compare-memberships/),
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview),
[notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[app privacy](https://developer.apple.com/app-store/app-privacy-details/), and
[license agreements](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement).

## Optional support links

Donation support is sufficient for the current GitHub-first direction. Add only
a real owner-approved destination to README/About or `.github/FUNDING.yml`;
do not interrupt a session or add payment infrastructure to ship this candidate.
Branding and any later commercial model remain separate decisions. An App Store
paid-app agreement, in-app purchases, subscriptions, and store marketing are not
requirements for this direct-distribution candidate.
