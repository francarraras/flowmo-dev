# Flowmo

Stop counting down. Start flowing up.

A Flowmodoro. You work until you stop. Rest is earned from how long you focused. One charcoal window. One circle that does not move.

**Behavior:** [`docs/PROJECT.md`](docs/PROJECT.md)
**Look:** [`docs/visual.md`](docs/visual.md)

## Open the window

```bash
cd ~/dev/flowmo
swift run
```

Leave that running. That is the app.

## Drive it from the terminal

Open a second terminal in the same folder. Paste one line at a time. Watch the window, not the text that prints.

```bash
cd ~/dev/flowmo

swift run flowmo start "try the loop"    # Prime
swift run flowmo skip                    # Focus
swift run flowmo capture "parked line"
swift run flowmo stop                    # Break
swift run flowmo skip                    # Reflection
swift run flowmo skip                    # Close
swift run flowmo skip                    # Idle
swift run flowmo status
```

**Skip** jumps Prime (2:00) and Reflection (3:00) so you are not sitting through them.

What should happen:

- After Start, the circle stays put. Start is gone.
- Focus counts up. Gold is rest you are earning.
- Break is gold.
- Close shows **Focused** and **Rested**. After the last Skip, Idle is empty again.
- **History** still has the parked line. Tap a card to open it.

Same session as the window. Same file: `~/.flowmo/world.json`.

```bash
swift run flowmo live      # ticking view of that session
swift run flowmo check     # core proofs
```

iPhone is a separate local app (`Apps/FlowmoPhone.xcodeproj`). The old tree in `~/Flowmo` is reference only.
