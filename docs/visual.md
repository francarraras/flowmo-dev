# Flowmo — visual pass (signed 2026-08-19)

Loop and acceptance stay locked. This pass only fills the empty white frame.

Captain choices:

- **Tighten.** Same compact window. Less vertical gap. Clock closer to the actions. No extra widgets.
- **Surface.** Black field. One cyan accent for timed rings and Start. Old iPhone timer is reference, not a theme pack, Home, or scores.
- **Chrome.** Hide the title. Keep traffic lights. Pin stays in the content, default off.

Layout (this pass):

- Default **300×300**. Resizable, capped **260–400 × 260–480**. Not a portrait document.
- Pin overlays the chrome. It does not own a row.
- Timed phases: **clock lives in the ring**. Skip stays visible. Focus stays a count-up with no ring.
- Resize scales the hero (clock / ring) with leftover space. Captions and Skip stay compact. `NSHostingView` only publishes min-size so the content can fill the window.
- Craft, not a theme pack: SF, size-specific tracking on the clock, press-down feedback, Skip contrast that reads on black, content clears the traffic lights. No glass, springs-on-everything, or extra chrome.

Out of this pass: menu bar, light/dark toggle, custom fonts, illustrations.

Done means the live window is still the locked loop, and it no longer reads as a blank document.
