# Developing Flowmo

See [installation](installation.md#build-from-source) for source builds.

## Checks

```sh
swift format lint --strict --recursive Package.swift Sources Tests Apps
swift test -Xswiftc -warnings-as-errors
swift run -Xswiftc -warnings-as-errors flowmo check
swift build -c release -Xswiftc -warnings-as-errors
```

Use a disposable `FLOWMO_HOME` for test sessions. Use the supported CLI for automation instead of editing the store directly. `flowmo status --json` includes session text; action responses do not echo it. Keep exports and private session text out of issues and test logs.

## Architecture and behavior

- [Domain vocabulary](../CONTEXT.md)
- [Product behavior](PROJECT.md)
- [Architecture](architecture.md)
- [Feature and test map](feature-map.md)
- [Visual design](visual.md)
- [Focus Guard](focus-guard.md)
- [Terminal view](live.md)
- [Release procedure](release.md)

The local downloads are independent of CloudKit. The separate entitled schemes retain CloudKit and widget support for contributors with suitable provisioning. See the release procedure for capabilities and platform checks.
