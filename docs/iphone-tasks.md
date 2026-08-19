# Flowmo — iPhone (tasks)

From [`iphone-design.md`](iphone-design.md). Done means [`iphone.md`](iphone.md) holds.

Signed by the captain on 2026-08-19. Implementation of this list is allowed.

Do not start a second engine. Do not add Home, tabs, Pause-during-focus, a focus progress ring, widgets, Live Activities, iCloud, history, or a theme pack. Do not open `~/Flowmo` except as visual reference.

---

1. **Spike**  
   iOS host links FlowmoCore. `Store(root:)` in the app container. Core builds for iOS (Package platforms only if needed). Background does not pause; cold start pauses unpaused `live`. Schedule-and-cancel a dummy timed notification. If spike fails, stop.

2. **Phone UI**  
   Compact SwiftUI loop matching Mac states and [`visual.md`](visual.md). Mute. No pin, no Guard.

3. **Attention**  
   Unmuted cue in foreground. Timed-phase notifications scheduled at phase start, cancelled on Skip/Stop. Tap opens, does not Continue.

4. **Prove**  
   Simulator loop, skip=stop, background, kill/Continue, mute in JSON, `swift run flowmo check`.

Anything not listed is a later slice.
