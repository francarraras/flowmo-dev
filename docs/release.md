# Release procedure

Flowmo 1.0 is a close-beta candidate, not yet an Apple-trusted external release.
The repository owner is recorded as Fran Carrara. Flowmo is the working name
until the owner reopens branding. An owner-authorized Mac-only friends-and-family
preview may be shared under the explicit limitations below.

## GitHub-first distribution

The near-term distribution target is a GitHub release with a Mac app and a
separate Mac terminal executable. App Store publication is not a prerequisite
or part of this candidate. No public download, donation address, or iPhone beta
link is configured yet; do not add invented destinations or describe a local
candidate as published.

On 2026-09-05 the owner ruled out paying for Apple Developer Program membership.
The chosen path is open source plus local-only Mac/terminal downloads, with
explicit ad-hoc signing and installation limitations, and a free Personal Team
iPhone build for personal use. Developer ID, notarization, TestFlight, and
entitled iCloud/widget delivery are outside this release scope. Membership is
not a pending purchase or a prerequisite for publishing the source. Manual
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

The owner chose an open-source direction; this working-tree candidate proposes
MIT in `LICENSE`, using the recorded copyright owner. Review that exact license
with the candidate before public release. Add an actual public support route,
privacy contact, and confidential security-report route. A donation can be a
README/About link and `.github/FUNDING.yml` once the owner supplies a destination;
no payment SDK or account system is needed. See [GitHub licensing](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
and [funding links](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository).

### Terminal candidate packaging

After the code and version metadata are reviewed, run from a clean committed
checkout:

```bash
./Scripts/package-cli
```

This builds the SwiftPM `flowmo` product for arm64 and x86_64, combines the
executables, ad-hoc signs with Hardened Runtime, and creates a versioned `.tar.gz`,
SHA-256 file, and manifest in ignored `dist/`. The archive includes an installer,
executable checksum, license, privacy policy, and readme. Packaging extracts the
exact archive and verifies its architectures, signature, checksum, version,
and isolated idle JSON response. It refuses existing output names, checks that
the embedded CLI version/build matches the Mac project, and never uploads,
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
executable checksum and preserves extended attributes, including quarantine.
After quitting running Flowmo instances, `./install.sh --replace` explicitly
upgrades an existing installation. `--prefix PATH` chooses another prefix.
Removing only `PREFIX/bin/flowmo` uninstalls the command and preserves sessions.
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
   under the **FlowmoPhoneLocal** target's Signing & Capabilities. Account login,
   agreements, and device trust remain actions for the owner.
3. Select that connected iPhone as the run destination and Run. If necessary,
   follow Xcode's on-device Developer Mode and provisioning instructions.

The local target uses its own bundle identifier and app-container store. It
does not request App Group, iCloud, or push entitlements and does not embed the
widget. The focus loop, recovery, exports, and local notification reminders
remain available. It does not read, migrate, or sync the entitled phone store.
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
- Package the app with `docs/FRIENDS_AND_FAMILY.txt` and the current `PRIVACY.md`.
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

`./Scripts/family-preview` is the executable form of the automated checks and
packaging rules in this section. The commands remain documented here so CI and
the release contract are independently reviewable.

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

5. Build and analyze the iPhone app and widget in the simulator:

   ```bash
   xcodebuild -project Apps/FlowmoPhone.xcodeproj -scheme FlowmoPhone -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
   xcodebuild -project Apps/FlowmoPhone.xcodeproj -scheme FlowmoPhone -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES analyze
   ```

6. Smoke-test the Mac window and `swift run flowmo status --json` against an
   isolated `FLOWMO_HOME`.
7. Launch and smoke-test on the intended latest macOS version and the latest-iOS
   iPhone 15, 16, and 17 simulators. Exercise each product phase, quit/sleep
   recovery, invalid-store repair, redacted diagnostics, full export, confirmed
   deletion, Focus Guard failure, phone unavailable state, and widget glance.
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
   enter from Classic's named **Focus scene**, Mini's named **Scene**, the
   sun-and-horizon primary action, and its explicit menu row. After **Back to
   window**, re-enter through a named action and the primary action. Confirm
   Scene remains movable and resizable and returns to the exact prior
   Classic/Mini presentation without changing the clock.
   On iPhone, confirm active unpaused Focus fills the frame with Distant
   Horizon in portrait and landscape, keeps Park thought and End focus
   reachable, and retains the timestamp clock across background/foreground.
   Check Dynamic Type and Reduce Motion, then terminate during Focus and
   confirm relaunch shows the compact Recovery Pause instead of resuming.
   Complete a session
   with a synthetic next step and confirm **Done** carries only that exact step
   into editable Idle without starting; repeat with a blank step. Stale
   competing completion remains a controller regression proof rather than a
   live smoke setup.
   For an entitled sync candidate, also test two signed-in devices: make an
   offline change on each, confirm distinct history unions, confirm simultaneous
   live starts block for a choose-one decision, verify account switching never
   uploads the prior account's pending data, and verify offline Delete All stays
   visibly incomplete until CloudKit confirms deletion.
8. Review `CHANGELOG.md`, `PRIVACY.md`, `SECURITY.md`, `PROVENANCE.md`, and
   `THIRD_PARTY_NOTICES.md`. Validate `Apps/PrivacyInfo.xcprivacy` and confirm it
   is present in the built Mac, phone, and widget bundles; then archive the exact
   test results with the release revision.
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
4. Run the required verification above, update `CHANGELOG.md`, and send testers
   a new build number with concise retest steps. Keep the previous signed build
   available for rollback.

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
