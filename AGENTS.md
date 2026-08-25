# Flowmo repo rules

Product behavior lives in [`docs/PROJECT.md`](docs/PROJECT.md). If chat, old code, or the frozen `~/Flowmo` tree conflicts with this file or PROJECT.md, this file and PROJECT.md win.

## Product invariants

- Flowmo is a Flowmodoro. Focus counts up until the user stops. It must not feel like a 25/5 countdown timer.
- The Mac window is the main product. The menu bar, terminal, CLI, JSON, and widget are supporting views or integrations.
- The intention is typed once at idle. Prime only displays it.
- Prime, break, and recall may use a determinate ring. Focus must not.
- There is one live session per local store. Clocks come from persisted timestamps, not UI timer ticks.

## Do not add

- Pause during Focus. Quit or sleep recovery returns paused with Continue and Restart; showing a window never resumes by itself.
- A 0–100% Focus ring or fixed Focus deadline.
- Home, tabs, setup screens, scores, streaks, flashcards, or a history dashboard.
- Accessibility control, process killing, or a helper for Focus Guard. If `hide()` fails, fail open.
- Widgets, iCloud, Watch, Live Activities, or theme work beyond the behavior already documented in this repo unless the user asks for that feature.
- Code copied from `~/Flowmo`. It is visual and formula reference only.

## Shipped behavior

- Mac loop and visual rules: [`docs/PROJECT.md`](docs/PROJECT.md) and [`docs/visual.md`](docs/visual.md).
- Focus Guard: [`docs/focus-guard.md`](docs/focus-guard.md).
- Menu-bar clock: [`docs/menu-bar.md`](docs/menu-bar.md).
- Living terminal: [`docs/live.md`](docs/live.md).
- Local iPhone app: [`docs/iphone.md`](docs/iphone.md).
- iPhone widget: [`docs/widget.md`](docs/widget.md). It is a glance over the phone App Group store, not a session controller.
- Roadmap only: [`docs/v2.md`](docs/v2.md).

## Change and preview loop

- For a bug or behavior change, reproduce with an isolated store or simulator, add a regression proof when practical, make the smallest fix, and run the relevant format, test, and core-proof gates. Update `CHANGELOG.md` for tester-visible changes.
- Keep intentions, full exports, store paths, and other private tester data out of prompts, logs, screenshots, commits, and issues; use redacted diagnostics.
- Before adding a dependency, SDK, action, snippet, asset, or font, verify its source, license, redistribution terms, privacy impact, and maintenance risk; update `PROVENANCE.md`, `THIRD_PARTY_NOTICES.md`, and privacy declarations when their facts change.
- CI must pass on every pushed candidate. A passing CI run is evidence, not permission to distribute.
- When the owner asks to prepare or redeploy a friends-and-family preview, increment the Mac build number, synchronize the changelog and tester guide, review and commit the candidate, then run `./Scripts/family-preview`. Commit its appended ledger receipt and mark it distributed or withdrawn only after owner review.
- Never overwrite a previous preview or automatically push, tag, notarize, upload, or share one. The owner approves every distributed build after the manual smoke checks in `docs/release.md`.

## Run

- Window: `swift run flowmo`
- Dock app: `xcodebuild -project Apps/Flowmo.xcodeproj -scheme Flowmo -configuration Release CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES`, then open `Flowmo.app` (`app.flowmo.mac`).
- iPhone: `xcodebuild -project Apps/FlowmoPhone.xcodeproj -scheme FlowmoPhone -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES` (`app.flowmo.phone`).
- CLI side door: `swift run flowmo status --json`
- Living view: `swift run flowmo live`
- Core proofs: `swift run flowmo check`
- Mac store: `~/.flowmo/world.json`, overridden by `FLOWMO_HOME`

Keep this file short. Put product decisions in PROJECT.md. Do not add generated planning pages, approval rituals, or duplicate task documents.
