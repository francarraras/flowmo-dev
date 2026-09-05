# Source and asset provenance

Last reviewed: 2026-09-05

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

The provisional crescent-and-horizon app icon was generated with Codex's
built-in OpenAI image generation tool on 2026-09-05 from an original text
prompt, without reference images or third-party brand material. The unchanged
master, exact prompt, SHA-256, and technical conversion details are recorded in
[`Apps/IconSource/README.md`](Apps/IconSource/README.md). The bundled PNGs are
local size conversions, not an added SDK or runtime service.

OpenAI's [Terms of Use](https://openai.com/policies/row-terms-of-use/#content)
assign its rights, if any, in generated output to the user to the extent allowed
by law; output is not guaranteed unique. This records the source terms, not a
claim of exclusive copyright or trademark clearance. The asset follows this
repository's current license. No stock-image license or additional attribution
obligation was identified. The generation prompt contained design requirements
only, with no session intentions, exports, tester data, or reference files.
Packaging the resulting static icon adds no data collection, network behavior,
or privacy-manifest requirement. Maintenance is limited to the checked-in PNGs
and Apple's asset-catalog format; final branding remains provisional.

AI assistance does not replace human review or establish ownership by itself.
For every release, the owner should retain a private ledger recording:

- contributor and employer/assignment status;
- source origin for material changes and assets;
- AI tool use and the human review performed;
- every external snippet, package, asset, font, generator, and its license;
- the release revision, dependency inventory, test evidence, and approval.

Reachable Git history currently contains the author names `Fran Carrara` and
`Francisco Antonio Carrara Strina`. Before external distribution, the owner must
record whether these are the same legal owner and use the correct copyright and
contracting name. Obtain written IP assignments before accepting work from any
other contributor or contractor.

Future contributors must attest that their contribution is theirs to license,
that required third-party notices are recorded, and that private user session
content or unauthorized third-party code was not supplied to an AI tool.
