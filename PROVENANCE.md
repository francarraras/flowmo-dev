# Source and asset provenance

Last reviewed: 2026-09-06

The project owner has represented that Flowmo's product concept, design, source
code, and current visual material are original personal work, created with AI
assistance, and were not copied or recreated from another product or codebase.
The frozen `~/Flowmo` tree is reference-only and is not a source of copied code.

The current repository audit found no shipped third-party packages, code,
images, fonts, binaries, or frameworks. See `THIRD_PARTY_NOTICES.md`.
CloudKit, Combine, and the notification frameworks are Apple platform
frameworks supplied by the operating system; no external SDK was added for
sync. CloudKit changes privacy and provisioning facts but adds no redistributable
third-party dependency.

The build 5 Focus Live Activity uses Apple's ActivityKit and WidgetKit
platform frameworks, with an original extension and timestamp-only projection.
It adds no package, downloaded asset, copied sample code, remote push service,
or external SDK. Apple's
[Food Truck sample configuration](https://github.com/apple/sample-food-truck#configure-the-sample-code-project)
was consulted as read-only evidence that an app and widget extension can use
Personal Team signing. None of its implementation or assets were incorporated.
Maintenance follows Apple's platform API and extension requirements; the
metadata shared with the system display is documented in [`PRIVACY.md`](PRIVACY.md).

The visual treatment introduced in build 5 uses two original assets generated on
2026-09-05 with Codex's built-in OpenAI image generation tool from text-only
design prompts, without reference images, third-party brand material, or
private session/tester data:

- The aperture-and-incision icon supplies the shared Mac/iPhone asset catalog.
  Its unchanged master and exact prompt are recorded in
  [`Apps/IconSource/flowmo-horizon-v2-receipt.md`](Apps/IconSource/flowmo-horizon-v2-receipt.md).
  Fourteen local size conversions fill the existing 19 icon slots. The earlier
  crescent-and-horizon master remains checked in as the historical build 4
  source; it no longer supplies the current catalog. See the
  [icon inventory](Apps/IconSource/README.md).
- Horizon Study is the unchanged generated PNG bundled by the `FlowmoLook`
  SwiftPM resource target for the native Focus canvases and tutorial. Its exact
  prompt, dimensions, SHA-256, source path, and rendering details are recorded in
  [`Apps/ArtworkSource/README.md`](Apps/ArtworkSource/README.md).

OpenAI's [Terms of Use](https://openai.com/policies/row-terms-of-use/#content),
checked on 2026-09-05, assign its output rights, if any, to the user to the extent
permitted by law; output need not be unique. This is not a claim of exclusive
copyright or trademark clearance. These assets follow the repository's
[MIT license](LICENSE). No additional stock-image license or attribution
obligation was identified.

Only static PNGs are shipped. No runtime AI, external SDK, font, network call,
new privacy API, analytics, or user-data processing was added. The image prompts
contained design requirements only. Existing privacy declarations remain
unchanged by this asset work. Maintenance is limited to the checked-in images,
SwiftPM resource packaging, and Apple's asset-catalog format. The product name
remains provisional, and this work does not replace build 4 preview artifacts.

## Documentation screenshots

The README includes three unchanged native UI captures from the local polish
check on 2026-09-05, recorded against source revision
`8f486ba83e23caa74d92a83faa0d6e557833ee09`. All visible intentions are synthetic
test text. The phone captures include Apple's Simulator frame; the Mac capture
shows the isolated Focus scene. They are screenshots of the implemented app,
not new generated artwork, edited screenshots, or evidence of a public release.

The originals are retained in the local `flowmo-polish/screenshots` evidence
folder. These byte-identical documentation copies are not bundled into the app:

| Repository file | Original capture | SHA-256 |
| --- | --- | --- |
| [`docs/screenshots/mac-focus-scene.png`](docs/screenshots/mac-focus-scene.png) | `05-mac-focus-scene.png` | `a0abc994507f40274b54ece9713d71e17fbbe50242a21083fce0183a9f3dcb4f` |
| [`docs/screenshots/iphone-focus.png`](docs/screenshots/iphone-focus.png) | `03-phone-focus.png` | `86588c40c7f4cafe978453e0370f0ec6eae04e8a5102f838045be160afc5d91e` |
| [`docs/screenshots/iphone-introduction.png`](docs/screenshots/iphone-introduction.png) | `01-phone-introduction.png` | `663742b5198ed100258ec3270449bfaddf4fd8603672cc8fd5443f1c0f7278ef` |

The app artwork and its source terms remain documented above. These captures
add no runtime resource, dependency, data collection, or network behavior.

## Contributor provenance

AI assistance does not replace human review or establish ownership by itself.
For every release, the owner should retain a private ledger recording:

- contributor and employer/assignment status;
- source origin for material changes and assets;
- AI tool use and the human review performed;
- every external snippet, package, asset, font, generator, and its license;
- the release revision, dependency inventory, test evidence, and approval.

On 2026-09-05, the owner confirmed that the Git author names `Fran Carrara` and
`Francisco Antonio Carrara Strina` both identify them. The copyright notice uses
Fran Carrara; the longer name identifies the same owner in the existing history.
Obtain written IP assignments before accepting work from any other contributor
or contractor.

Future contributors must attest that their contribution is theirs to license,
that required third-party notices are recorded, and that private user session
content or unauthorized third-party code was not supplied to an AI tool.

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
