# Flowmo

Stop counting down. Start flowing up.

**Product behavior:** [`docs/PROJECT.md`](docs/PROJECT.md).

The CLI in this folder is an early sketch. It is not how people use Flowmo.

## On this Mac

```bash
cd ~/dev/flowmo
swift build
alias flowmo="$(swift build --show-bin-path)/flowmo"

swift run                # compact window (the product)

# same live session, side door:
flowmo start writing
flowmo skip
flowmo capture "call the accountant"
flowmo stop
flowmo continue          # after quit/sleep recovery
flowmo status --json
flowmo cancel
```

Sessions live in `~/.flowmo/world.json`. The iPhone app is `Apps/FlowmoPhone.xcodeproj` (bundle `app.flowmo.phone`, local container store). The old tree in `~/Flowmo` is reference only.
