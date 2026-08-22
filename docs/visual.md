# Flowmo — visual rules

Direction **3 — Phase atmosphere**. Same compact frame. The room changes with the loop.

- **Tighten.** Same compact window. Less vertical gap. Clock closer to the actions. No extra widgets.
- **Tokens.** Shared `FlowmoLook`: `Atmosphere.of(status)` gives `field`, `ink`, `mute`, `faint`, `line`, `well`, `chrome`. Each root sets `\.atmosphere` once; every pane reads it. Idle aliases stay on `Look` for surfaces with no phase.
- **Accent.** Gold `#C8A24B` is earned rest only — the 2pt strip under the Focus clock, nowhere else. Start and Continue are ink on field. Timed rings use atmosphere `line`/`mute`, not cyan. There is no brand color.
- **Phase atmosphere.** Idle dry charcoal; Prime still and low-contrast; Focus a black room with an oversized count-up, the gold strip, and chrome nearly gone; Break warm; Recall editorial; Close a receipt, back in the idle room.
- **Chrome.** Hide the title. Keep traffic lights. Pin stays in the content, default off. Mute/pin opacity follows `chrome`.

Palettes:

| Phase | field | ink | mute | faint | line | chrome |
| --- | --- | --- | --- | --- | --- | --- |
| Idle | `#0A0B0D` | `#DDDEE1` | `#6E747D` | `#3A3F47` | `#1B1E23` | 1 |
| Prime | `#08090C` | `#9BA0A8` | `#4A4F57` | `#2A2E35` | `#16181D` | 0.45 |
| Focus | `#000000` | `#FFFFFF` | `#585D66` | `#2A2E35` | `#15171B` | 0.25 |
| Break | `#12100C` | `#D9CFC0` | `#77705F` | `#44403A` | `#211E18` | 0.8 |
| Recall | `#0C0D10` | `#E9EAEC` | `#7C828B` | `#3A3F47` | `#1D2026` | 1 |
| Close | idle | | | | | |

Layout (this pass):

- Default **300×300**. Resizable, capped **260–400 × 260–480**. Not a portrait document.
- Pin overlays the chrome. It does not own a row.
- Every phase opens with a tracked uppercase kicker: intention on Prime and Focus, the earned line on Break, the countdown on Recall, `Session` on Close.
- Text entry is a hairline under the text, not a filled well. Recall is the one written line of the loop, so it is serif italic.
- Timed phases: **clock lives in a 1.5pt ring**. Skip stays visible while unpaused. Focus stays a count-up with no ring.
- Close is a receipt: Intention, Focus, Rest taken, Parked, Recall — label mute, value ink, hairline rules.
- Paused shows a `Paused` kicker over Continue, in whatever room the session stopped in.
- Resize scales the hero (clock / ring) with leftover space. Kickers, footnotes, and Skip stay compact. `NSHostingView` only publishes min-size so the content can fill the window.
- Craft, not a theme pack: SF, size-specific tracking on the clock, press-down feedback, content clears the traffic lights. Rooms cross-fade over ~0.9s; nothing else animates. No generic glassmorphism.

Menu bar and widget follow the same atmosphere ink and field. Out of this pass: custom fonts, illustrations.

Done means Idle, Prime, Focus, Break, Recall, and Close read as different atmospheres, and the locked loop is unchanged.
