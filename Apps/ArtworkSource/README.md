# Horizon Study — generation receipt

Generated on 2026-09-05 with Codex's built-in OpenAI image generation tool from
one original text-only design prompt. No reference image, third-party asset,
brand material, session intention, export, or private tester data was supplied.
The artwork is decorative and makes no claim about the product's eventual name.

## Source and integration

The unchanged generated file is
[`Sources/FlowmoLook/Resources/HorizonStudy.png`](../../Sources/FlowmoLook/Resources/HorizonStudy.png).
It is **1586 × 992 pixels, opaque RGB**. The prompt requested 2560 × 1600 or
similar; these are the actual returned dimensions. No image editing, creative
repainting, cropping, or resampling was applied to the stored master.

SHA-256:
`760650f729af157071c7e3e4b9d331462bb2efffcf23933ce963202a7d9a6400`.

Original tool output:
`/Users/facspro/.codex/generated_images/01a06e6b-98fc-7f33-b5f8-5b6154922ddb/exec-b1eed642-2471-4917-a0fb-8e94e374049a.png`.
The bundled file and original output have the same SHA-256.

`Package.swift` processes the image once as a `FlowmoLook` resource.
`DistantHorizonBackdrop` and `IntroductionView` load it through `Bundle.module`.
The native views scale and crop the image to fit their frames and apply local
contrast overlays; the stored PNG remains unchanged. The Focus canvas applies
a small ambient luminance change only while active and Reduce Motion is off.
None of this imagery represents Focus progress or drives a session clock.

Visual inspection found a dark graphite horizon and controlled ivory/champagne
incision, with empty space for the app's real text and controls. The generated
image contains no interface, letters, clock digits, device frame, or watermark.
This receipt records the source and integration, not a device-delivery result.

## Terms, privacy, and maintenance

OpenAI's [Terms of Use](https://openai.com/policies/row-terms-of-use/#content),
checked on 2026-09-05, assign its output rights, if any, to the user to the extent
permitted by law; uniqueness is not guaranteed. The asset follows this
repository's [MIT license](../../LICENSE). No separate stock-image license or
attribution obligation was identified. See [project provenance](../../PROVENANCE.md)
and [third-party notices](../../THIRD_PARTY_NOTICES.md).

Only a static PNG is bundled. It adds no runtime AI, downloaded asset, external
SDK, font, network request, privacy API, telemetry, or user-data processing.
Existing privacy declarations do not change for this asset. Maintenance is
limited to the checked-in image, SwiftPM resource packaging, and native layout.
The work remains Unreleased and does not replace build 4 preview artifacts.

## Exact generation prompt

> Use case: stylized-concept. Create ONE original production background artwork for Flowmo, a premium native macOS and iPhone focus instrument. This is the actual image asset to ship in the app, not a mockup: NO interface, NO text, NO numbers, NO device frame. Landscape 2560x1600 or similar high resolution. Art direction: disciplined optical sculpture, tangible satin graphite and obsidian, an almost-black #090A0C field, an exceptionally fine ivory-to-muted-champagne illuminated horizon. A vast dark convex surface occupies the lower half, with a precise shallow arc at about 64% canvas height. At the arc's middle, a subtle second recessed dark plane produces a tiny slit of warm light: architectural, quiet and tactile, like a physical precision instrument photographed in a dark studio. Very fine controlled grain, exquisite anti-aliased edges, gentle local tonal variation and a faint soft reflected light below. Top 43% remains almost uniformly near-black and empty for the actual app's text; bottom 18% remains very dark for controls. The center 40% of the width must retain the composition when cropped to an iPhone portrait frame. The left and right edges melt seamlessly into the same near-black field. Light should be restrained and sharply controlled; one clean visual idea. Do NOT make a sun, moon, crescent, planet texture, crater, star field, fantasy scene, rainbow gradient, smoke, broad blurry gold blob, lens flare or ornate 3D logo. No progress ring or countdown symbolism. Premium editorial product photography mood, distinctive but calm enough to look at for hours. Original composition, no imitation of any existing brand.
