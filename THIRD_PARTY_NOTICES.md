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

The bundled provisional app icon is original AI-generated output created with
OpenAI's built-in image generation tool on 2026-09-05, then resized locally.
It is not a downloaded stock image or a redistributed OpenAI logo. Source,
output-ownership terms, and the exact prompt are recorded in
[`PROVENANCE.md`](PROVENANCE.md) and
[`Apps/IconSource/README.md`](Apps/IconSource/README.md). No additional
third-party asset license or attribution notice was identified for this icon.

The pinned `actions/checkout` GitHub Action is build infrastructure and is not
distributed in the app binary.

This is a release inventory, not a promise about future revisions. Re-run the
dependency, asset, and attribution review whenever a package, SDK, font, image,
snippet, generated artifact, or build action is added.
