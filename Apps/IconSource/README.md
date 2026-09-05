# App icon sources

The current shared Mac/iPhone icon catalog uses the original
**aperture-and-incision** mark generated on 2026-09-05 with Codex's built-in
OpenAI image generation tool. No reference image, third-party asset, font,
brand, or private user data was supplied. The working name remains Flowmo.

## Current Unreleased catalog

`flowmo-horizon-v2-master.png` is the unchanged **1254 × 1254 opaque RGB** output.
Its SHA-256 is
`54bf78847e82aa4efe4a65a692e301adb04f8f05f17f836f2b1fccd3b5903e9f`.
The exact prompt and original tool output path are in the
[generation receipt](flowmo-horizon-v2-receipt.md).

The shared `../Assets.xcassets/AppIcon.appiconset` contains 14 opaque RGB PNGs
for 19 icon slots: Mac 16, 32, 128, 256, and 512 points at 1×/2×; iPhone 20, 29,
40, and 60 points at 2×/3×; and the 1024-pixel iOS icon. Native `sips` size
conversions from the v2 master now supply every slot. Catalog dimensions and
opacity were verified after replacement. No artwork was creatively repainted,
cropped, pre-masked, or given an outer tile shadow. The master itself is not an
application resource. Earlier build 4 preview artifacts remain unchanged.

Apple's [asset-catalog configuration guide](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
and [App Icon format reference](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/AppIconType.html)
define the icon slots. Its [app-icon design guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/)
calls for square, unmasked artwork and lists sRGB as a supported color space.
These references were checked on 2026-09-05. The conventional PNG catalog
preserves the existing macOS 14 and iOS 17 deployment targets; it adds no Icon
Composer dependency or minimum OS requirement.

OpenAI's [Terms of Use](https://openai.com/policies/row-terms-of-use/#content),
checked on 2026-09-05, assign its output rights, if any, to the user where law
permits; output may not be unique. The assets follow the repository's
[MIT license](../../LICENSE). See [project provenance](../../PROVENANCE.md).
Static icon packaging adds no runtime AI, network behavior, analytics, privacy
API, or user-data processing. Maintenance is limited to the checked-in PNGs
and the native catalog format.

## Historical build 4 source

`flowmo-provisional-master.png` is the earlier crescent-and-horizon icon,
generated on 2026-09-05 with the same built-in tool. It remains unchanged at
**1254 × 1254 opaque RGB** pixels, with SHA-256
`f07ff1acef23dfeb2edd967e1a9f9e909eba757cecceacb14b3178623e5ed0ab`.
It supplied the build 4 icon derivatives; it is retained for provenance and
no longer supplies the current asset catalog. The original prompt requested
1024 × 1024, and local `sips` derivatives supplied each required size with the
system sRGB profile. The source master is not an application resource.

Exact generation prompt:

> Use case: logo-brand. Asset type: provisional native macOS and iPhone app icon master, square 1024 by 1024, full-bleed opaque artwork. Create one original minimal icon for an open-ended focus app whose existing design is charcoal, warm white, and quiet gold. A single thin, beautifully precise warm-gold curved horizon across the lower middle, with one luminous golden crescent rising just above its center, suggesting a calm aperture opening and earned rest. Large simple memorable silhouette legible at tiny sizes, generous negative space, dark graphite #090A0C field, gold around #E8BA5C, very restrained soft glow. Refined flat native app-icon artwork with subtle depth, no photographic landscape, no busy textures, no UI screenshot, no letters, no wordmark, no clock digits, no progress ring, no checkmark, no brand reference or watermark. Fill the square; do not bake in rounded corners or external drop shadows; operating systems will mask it.
