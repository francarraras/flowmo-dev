# Flowmo — living terminal view

`flowmo live` stays open and ticks the **same** session as the window (`~/.flowmo/world.json`). It is a view, not a command list.

The file is internal storage, not a supported write API. Scripts should read
`flowmo status --json` and use supported CLI actions; they must not modify
`world.json` directly.

## In

- Redraw Core status every 250 ms (idle / prime / focus / break / recall / close beat, including recovery pause).
- Advance timed phases via the same `Engine.sync` the window uses.
- `q`, Esc, or Ctrl+C leaves the view. Does **not** pause or stop the session.

## Out

Pause, Start, Skip, scores, replacing `swift run` (no args still opens the window).
