# Flowmo

Stop counting down. Start flowing up.

**Source of truth:** [`docs/PROJECT.md`](docs/PROJECT.md) — updated vision, locked v1, handoff.

The CLI in this folder is an early sketch. It is not how people use Flowmo.

## On this Mac

```bash
cd ~/dev/flowmo
swift build
alias flowmo="$(swift build --show-bin-path)/flowmo"

flowmo start writing     # setup + 2 min prime
flowmo skip              # skip prime / break / recall
flowmo capture "call the accountant"
flowmo stop              # end focus, start earned break
flowmo status
flowmo pause
flowmo resume
flowmo cancel
```

Sessions live in `~/.flowmo/world.json`. The old iPhone app in `~/Flowmo` is reference only.
