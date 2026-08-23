# Release procedure

Flowmo 1.0 is a close-beta candidate, not yet an Apple-trusted external release.
The repository owner is recorded as Fran Carrara. Flowmo is the working name
until the owner reopens branding. An owner-authorized Mac-only friends-and-family
preview may be shared under the explicit limitations below.

## Free personal testing

An Apple Account with Xcode's Personal Team is enough for the owner to run local
Mac builds and ordinary personal-device apps that use only supported free-team
capabilities. Apple limits this path to personal use; device registrations and
provisioning profiles expire after seven days. It does not provide TestFlight,
Developer ID, notarization, or friend distribution. Flowmo's current iPhone and
widget targets require an App Group, so they are simulator-only until paid-team
provisioning is configured. The unavailable path can also be exercised there.

Do not describe an ad-hoc Mac build as signed, notarized, Apple-reviewed, or a
general release.

## Informal Mac friends-and-family preview

Until Developer Program enrollment works, the owner may share a narrowly scoped
Mac engineering preview with people who know and trust the sender. This path is
not available for the iPhone app or widget.

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

## Required verification

From a clean checkout of the candidate revision:

1. Run `swift format lint --strict --recursive Package.swift Sources Tests Apps`.
2. Run `swift test -Xswiftc -warnings-as-errors`.
3. Run `swift run -Xswiftc -warnings-as-errors flowmo check` and
   `swift build -c release -Xswiftc -warnings-as-errors`.
4. Build and analyze the Mac app:

   ```bash
   xcodebuild -project Apps/Flowmo.xcodeproj -scheme Flowmo -configuration Release -sdk macosx -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
   xcodebuild -project Apps/Flowmo.xcodeproj -scheme Flowmo -configuration Debug -sdk macosx -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES analyze
   ```

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
   Confirm a second Mac process cannot mutate the first process's lifecycle and
   an immediate CLI Continue survives crash recovery without losing frozen
   time. Confirm Focus always counts up with no pause or progress ring.
8. Review `CHANGELOG.md`, `PRIVACY.md`, `SECURITY.md`, `PROVENANCE.md`, and
   `THIRD_PARTY_NOTICES.md`. Validate `Apps/PrivacyInfo.xcprivacy` and confirm it
   is present in both the built phone app and widget bundles; then archive the
   exact test results with the release revision.
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

## Before friends receive a build

These are blocking, not optional polish:

- Enroll the legal owner in the paid Apple Developer Program. Apple currently
  lists it as US$99/year. Create the app identifiers, App Group, certificates,
  and provisioning profiles under that team.
- Create the App Store Connect app record. Increase `CURRENT_PROJECT_VERSION`
  for every uploaded build and keep the phone app and widget versions aligned.
  Complete the required TestFlight metadata, review notes, export-compliance
  answers, privacy answers, and tester groups before inviting anyone.
- Decide the distribution paths. External TestFlight builds receive TestFlight
  App Review, expire after 90 days, and need beta description, review notes, and
  a monitored feedback email. A direct Mac beta needs Developer ID signing,
  secure timestamping, Hardened Runtime, notarization, and stapling.
- Supply an app icon/working visual identity, hosted privacy-policy URL, in-app
  privacy access, support contact, and confidential security channel.
- Tell testers that Apple TestFlight automatically collects crash and usage
  data. Use TestFlight crash reports plus Flowmo's opt-in redacted diagnostic
  export; do not add third-party analytics merely to discover bugs.
- Confirm export-compliance answers for every build. The current iPhone targets
  declare no non-exempt encryption because Flowmo ships no cryptography; review
  that declaration whenever networking or cryptographic code changes.
- Re-audit required-reason APIs and `Apps/PrivacyInfo.xcprivacy` whenever file,
  device, preferences, or third-party SDK APIs change.
- Confirm the legal owner name and Git author aliases in `PROVENANCE.md`. Use
  Apple's standard EULA for an App Store/TestFlight distribution unless counsel
  chooses a custom agreement. Direct Mac distribution needs separately
  presented terms. Get counsel before relying on custom consumer, liability,
  confidentiality, feedback-IP, or commercial terms.
- Tag only a clean, reviewed revision. Retain the prior signed build, symbols,
  changelog, and rollback notes.

Official Apple references: [membership
comparison](https://developer.apple.com/support/compare-memberships/),
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview),
[notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[app privacy](https://developer.apple.com/app-store/app-privacy-details/), and
[license agreements](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement).

## Before charging

Branding and the eventual business entity remain deferred decisions. Before a
paid App Store release, the Account Holder must accept Apple's Paid Apps
Agreement and complete banking/tax setup. Entity, consumer-law, tax, subscription,
and custom-license choices require jurisdiction-specific professional advice;
Estonian e-residency is not assumed by this codebase.
