# Flowmo

### Focus at your own pace. Take the rest you earn.

Flowmo is an open-source focus timer for Mac, iPhone, and the terminal. Set one intention, let the clock count up, and stop when you’re ready. Your focus time earns your break: **50 minutes of focus gives you 10 minutes of rest** at the default ratio.

**[Download for Mac](https://github.com/francarraras/flowmo-dev/releases/tag/v1.0.0-preview.6)** · [Install on iPhone](docs/installation.md#iphone-with-xcode) · [Use the terminal](#in-the-terminal)

## See it in 25 seconds

https://github.com/user-attachments/assets/825c43f5-21b6-424b-bde2-2ae771d6c329

## Make room for one thing

1. **Set an intention.** Write what you want to work on. Take a moment to settle in, or jump straight into Focus.
2. **Follow your own rhythm.** The clock counts up until you stop. Park a passing thought without leaving your session.
3. **Rest, then return.** Take your earned break and leave an optional next step for next time.

There’s no fixed Focus deadline. If you quit or your Mac sleeps, Flowmo keeps your place and waits for you to continue.

![Flowmo on Mac: an open-ended Focus clock over a quiet horizon](docs/screenshots/mac-focus-scene.png)

## A quiet place to focus

- **Mac:** a compact window, a menu-bar clock, and a larger Focus scene. Optional Focus Guard adds friction when you open selected apps.
- **iPhone:** the same focus-and-rest rhythm, with a Focus clock on the Lock Screen and supported Dynamic Island.
- **Terminal:** start a session, park a thought, or keep the clock beside your work. The terminal and Mac app share the same local session.

Sessions stay on your device. There’s no Flowmo account, advertising, or analytics service. Export or delete your data from the app whenever you choose. [Privacy](PRIVACY.md)

## Get started

| Platform | Get Flowmo | Requirements |
| --- | --- | --- |
| Mac | [Download the Mac ZIP](https://github.com/francarraras/flowmo-dev/releases/download/v1.0.0-preview.6/Flowmo-1.0-build6-macOS-universal-family-preview.zip) | macOS 14+, Apple silicon or Intel |
| Terminal | [Download the CLI archive](https://github.com/francarraras/flowmo-dev/releases/download/v1.0.0-preview.6/Flowmo-1.0-build6-macOS-universal-cli.tar.gz) | macOS 14+ |
| iPhone | [Install with Xcode](docs/installation.md#iphone-with-xcode) | iOS 17+, a Mac, and a free Apple Account |

Flowmo is currently a **public preview**. The Mac download is not notarized, so macOS may require [Open Anyway](https://support.apple.com/102445). Free iPhone signing needs refreshing every seven days. Mac and iPhone sessions do not sync in these builds.

[Installation, updates, and removal](docs/installation.md) · [Release notes and known limitations](https://github.com/francarraras/flowmo-dev/releases/tag/v1.0.0-preview.6)

## In the terminal

```sh
flowmo start "Write the next section"
flowmo skip                          # Start Focus
flowmo capture "Check this later"     # Park a thought
flowmo live                           # Keep the clock in view
```

Use `flowmo stop` to start your earned break. Run `flowmo --help` for all commands, or just `flowmo` to open the Mac window. Intentions typed in commands may be saved in your shell history.

## Build it, improve it, make it yours

With Xcode and Swift 6 installed:

```sh
git clone https://github.com/francarraras/flowmo-dev.git
cd flowmo-dev
swift run flowmo
```

[Development guide](docs/development.md) · [Report a bug](https://github.com/francarraras/flowmo-dev/issues/new?template=bug-report.yml) · [Report a security issue](SECURITY.md)

Flowmo is free and open source under the [MIT license](LICENSE).
