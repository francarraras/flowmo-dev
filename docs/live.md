# Flowmo — living terminal view

`flowmo live` stays open and ticks the **same** session as the window (`~/.flowmo/world.json`). It is a view, not a command list.

The file is internal storage, not a supported write API. Scripts should read
`flowmo status --json` and use supported CLI actions; they must not modify
`world.json` directly.

## In

- Redraw Core status every 250 ms (Idle / Prime / Focus / Break / Reflection / Close Beat, including Recovery Pause).
- Advance timed phases via the same `Engine.sync` the window uses.
- `q`, Esc, Ctrl+C, or Ctrl+D leaves immediately, without pressing Return. Does **not** pause or stop the session.
- Uses the terminal's alternate screen and restores the shell screen, cursor, and input settings on exit, error, and ordinary termination signals.
- Requires interactive terminal input and output. For pipes or redirected output, use `flowmo status` or `flowmo status --json`.

`flowmo live --help` explains the view without opening it. Every command accepts
`--help` before any action; unsupported options and extra operands fail without
changing the session. Put `--` before literal intention, parked-thought, or next-step
text that begins with a hyphen. `flowmo --version` identifies the installed build.

## Out

Pause, Start, Skip, scores, or replacing `swift run flowmo` as the window launcher.
