# Flowmo — visual rules

One charcoal square. One circular aperture that does not move. Phase is what the aperture holds. Gold is earned rest only.

- **Field** `#090A0C` with a warm radial well. **Ink** `#F3F1EA`. Mute/faint stay of that ink.
- **Type.** SF Rounded on clock, captions, and fields. No serif. No italic as identity.
- **Aperture.** Fixed circle, matched across phases. 5pt track, inner highlight, gold glow on Break. The hole is a lunar face: surface turns, light stays. Maria stay charcoal. Idle breathes unless Reduce Motion. Reduce Motion freezes the face.
- **Grid.** Every phase uses the same slots: 44pt caption, aperture, verb (36 Mac / 44 phone), then reserved idle chrome (Today / History / New, Guard on Mac). Live phases keep that chrome empty so Start → Prime does not grow the hole into the verbs. Skip/Continue/Start sit on the same baseline. Close keeps the intention in the caption and an empty verb so the circle does not jump.
- **Idle.** Field placeholder: **Intention**. The box starts empty and stays empty after Close. **New** clears a typed line you have not started. Lunar aperture. Start in the verb slot. Footer: Today, History, New. Mini idle is the aperture plus Start; tap the tile to expand and type.
- **History.** Same well cards. Collapsed: intention, date in mute, focus clock, and a count if there is writing. Tap opens that card only. Intention wraps. **Focused** stays ink. **Rested** is gold. **Parked** and **Reflection** appear only when they exist. Tap again, or tap another, to close. Height eases 0.28s. No sheet.
- **Prime.** Intention in the caption, cue **Prepare**. Clock in a graphite ring. Skip as text.
- **Focus.** Intention in the caption, cue **Focus**. No ring. Numerals fill the hole. Gold accrual with **no end cap**. `+` and Stop share the verb slot. Capture replaces that row with **Park** / **Discard**.
- **Break.** Caption: **Time to recharge**. Same ring geometry; progress is gold.
- **Reflection — 3:00.** Writing lives in the caption slot (same field as Intention), not inside the circle. Clock fills the hole like Prime. Skip stays in the verb slot. Return ends the beat.
- **Close.** Intention in the caption. Two named figures in the hole — **Focused** and **Rested**. Tap the frame to leave. No receipt. No “click to dismiss.”
- **Paused.** Aperture frozen. **Restart** and **Continue** occupy the verb slot. Restart primes the same intention again. Continue resumes the frozen clocks. No Paused banner.
- **Chrome.** Hidden title, traffic lights. Classic: mute, pin, shrink on the right. Mini: mute + pin on the left (clear of the traffic lights), expand on the right. Focus chrome opacity 0.35 on Classic; Mini chrome stays at 1. The wall does not fade.
- **Buttons.** Start/Continue: one ink chip that brightens and glows on hover. Skip/Stop/History/Guard/New: mute until hover — ink, a capsule well, and a 1pt ink stroke around the capsule. No underline. Chrome icons: ink + circular well. No grow-as-affordance.
- **Clock.** SF Rounded `.medium`, tabular. Timed ~36–40pt; Focus ~52–56pt.
- **Motion.** Phase: the circle stays put. Ring and hole assemble in place — four arcs click together, contents implode, nothing flies off or slides into the verbs. Captions and verbs ease (0.28s). Clock: numericText. Ring trim eases. No wallpaper fade. Lunar face turns in 96s (light fixed). Focus count grows once at **5 / 10 / 15 / 30 / 45 / 60**. Break last **10s** pulse each second (gold glow only — the circle does not move). Reduce Motion fades the assemble and skips grow, race, and the turn.

**Modes.** Two fixed sizes; the window does not resize freely.

- **Classic — 320×460.** The full instrument: caption, aperture, verb, idle chrome (Today, History, Guard). Fields are `FlowField`: delayed autofocus; a single hairline marks the slot, and it brightens and blooms on focus. No key legend. Intention Return starts; capture **Park** / **Discard** (Return / Esc still work); recall Return skips (text already saved as you type).
- **Mini — 168×176.** Aperture owns the tile. Clock (and gold accrual on Focus) in the hole; verb on the lower arc. Mute and pin sit left; expand sits right. No fields. Typing (intention, capture, recall) expands to Classic. Tap the Mini tile on idle or reflection to expand. `+` in Mini Focus opens capture in Classic.

Shared tokens live in `FlowmoLook` (`Atmosphere.canvas`, `Aperture`, `ApertureRing`, `PhaseColumn`, `InstrumentClock`, `Accrual`, `InkButton`, `QuietButton`, `RecoveryVerbs`). Mac fields live in `FlowField`. Menu bar and widget use the same field and ink. Idle glance is mute; paused is faint.

Out: theme packs, glass as identity, Focus progress ring, uppercase kickers as a system, serif inside the hole.
