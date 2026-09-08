# Third-party notices

Last reviewed: 2026-09-05

No third-party code, packages, fonts, images, frameworks, or other redistributable
assets were found in the Flowmo application at this revision. The app imports
Apple platform frameworks supplied by the operating system.
The private sync implementation uses Apple's CloudKit framework and service; it
does not redistribute a third-party SDK.
The local Focus Live Activity likewise uses Apple's ActivityKit and WidgetKit
frameworks supplied by the operating system. No sample code or assets were
copied; the read-only platform reference is recorded in
[`PROVENANCE.md`](PROVENANCE.md). No external dependency or additional asset
license was introduced.

The current aperture-and-incision app icon and bundled Horizon Study artwork
are original AI-generated output created with Codex's built-in OpenAI image
generation tool on 2026-09-05. They are not stock images or OpenAI brand assets.
The icon has local size derivatives; Horizon Study is the unchanged generated
PNG in the shared SwiftPM resources. The historical crescent icon source is
retained for build 4 provenance and no longer supplies the current catalog.

Source terms and the asset inventory are recorded in
[`PROVENANCE.md`](PROVENANCE.md), [icon records](Apps/IconSource/README.md), and
[artwork records](Apps/ArtworkSource/README.md). The generated assets follow the
repository's [MIT license](LICENSE). No additional third-party asset license or
attribution notice was identified. These static images add no runtime AI,
external service, privacy API, or user-data processing.

The README's unedited native screenshots use synthetic session text; the iPhone
captures include Apple's Simulator frame. They are documentation only and are
not bundled in the application. Their origins and byte-identical hashes are
recorded under [documentation screenshots](PROVENANCE.md#documentation-screenshots).

The pinned `actions/checkout` GitHub Action is build infrastructure and is not
distributed in the app binary.

This is a release inventory, not a promise about future revisions. Re-run the
dependency, asset, and attribution review whenever a package, SDK, font, image,
snippet, generated artifact, or build action is added.

## Launch media and tutorial illustrations — 2026-09-07

Three original HTML Canvas illustrations are bundled in FlowmoLook for the
existing Mac/iPhone tutorial. Exact instructions remain native accessible text;
images use synthetic examples only. No font files, renderer, new privacy API,
network service, or application dependency is bundled. Assets follow this repo's
MIT license. Remotion 4.0.522 and React 19.2.8 were used only as offline media
production tools; their separate terms and source receipts are recorded in
[media provenance](docs/media/PROVENANCE.md) and
[media notices](docs/media/THIRD_PARTY_NOTICES.md). The editable source is in the
release's media pack. Published build 6 binaries predate this source update.

The installation guide also reproduces an owner-supplied macOS warning capture
for instructional reference. Apple's interface remains Apple's material and is
not relicensed under MIT. The unchanged image is documentation only; see
[its provenance](PROVENANCE.md#mac-first-launch-help--2026-09-08).
