# Provisional app icon

Generated on 2026-09-05 with Codex's built-in OpenAI image generation tool.
No reference image, third-party asset, font, or brand was supplied. This is a
temporary visual identity; it does not settle the future app name.

`flowmo-provisional-master.png` is the unchanged 1254 × 1254 opaque RGB output.
Its SHA-256 is
`f07ff1acef23dfeb2edd967e1a9f9e909eba757cecceacb14b3178623e5ed0ab`.
The prompt requested 1024 × 1024; technical derivatives supply the exact sizes.

The shared `../Assets.xcassets/AppIcon.appiconset` contains 14 opaque PNGs for
19 icon slots: Mac 16, 32, 128, 256, and 512 points at 1×/2×; iPhone 20, 29, 40,
and 60 points at 2×/3×; and the 1024-pixel iOS icon. macOS `sips` resampled the
master directly for each pixel size and embedded the system sRGB profile. No
artwork was repainted, cropped, pre-masked, or given an external drop shadow.
This preserves the full-bleed master and leaves platform masking to the system.
The source master is not an application resource.

Apple's [asset-catalog configuration guide](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
and [App Icon format reference](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/AppIconType.html)
define the icon slots. Current [app-icon design guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/)
calls for square, unmasked artwork and lists sRGB as a supported color space.
These references were checked on 2026-09-05. This conventional PNG catalog
preserves the existing macOS 14 and iOS 17 deployment targets; it does not add
Icon Composer or a new minimum OS requirement. Dock and Home Screen appearance
still belong to native release smoke checks.

OpenAI's [Terms of Use](https://openai.com/policies/row-terms-of-use/#content)
assign its rights, if any, in output to the user to the extent permitted by law,
and explain that output may not be unique. See the repository's
[`PROVENANCE.md`](../../PROVENANCE.md) and current [`LICENSE`](../../LICENSE).
The static icon introduces no runtime network calls, analytics, or user-data
processing. No session content or private tester data was used in generation.

Exact generation prompt:

> Use case: logo-brand. Asset type: provisional native macOS and iPhone app icon master, square 1024 by 1024, full-bleed opaque artwork. Create one original minimal icon for an open-ended focus app whose existing design is charcoal, warm white, and quiet gold. A single thin, beautifully precise warm-gold curved horizon across the lower middle, with one luminous golden crescent rising just above its center, suggesting a calm aperture opening and earned rest. Large simple memorable silhouette legible at tiny sizes, generous negative space, dark graphite #090A0C field, gold around #E8BA5C, very restrained soft glow. Refined flat native app-icon artwork with subtle depth, no photographic landscape, no busy textures, no UI screenshot, no letters, no wordmark, no clock digits, no progress ring, no checkmark, no brand reference or watermark. Fill the square; do not bake in rounded corners or external drop shadows; operating systems will mask it.
