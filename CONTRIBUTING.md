# Contributing

Thanks for helping with Remote for MusicCast. Bug reports, reports from receivers we haven't tested, fixes and features are all welcome.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to help

- **Report a bug** with the [bug report form](https://github.com/azagsam/musiccast-remote/issues/new?template=bug_report.yml).
- **Tell us how it works with your receiver.** Only the R-N602 has been tested. A [receiver report](https://github.com/azagsam/musiccast-remote/issues/new?template=receiver_report.yml) helps even if everything works.
- **Suggest a feature** with the [feature request form](https://github.com/azagsam/musiccast-remote/issues/new?template=feature_request.yml).
- **Send a pull request.** Issues labeled [`good first issue`](https://github.com/azagsam/musiccast-remote/labels/good%20first%20issue) are a good place to start.

## Building

You need macOS 13 or later and the Xcode Command Line Tools with Swift 5.9 or later. Full Xcode isn't needed.

```sh
git clone https://github.com/azagsam/musiccast-remote.git
cd musiccast-remote
swift build                 # quick debug build while you work
./build.sh                  # universal release build, packaged as build/Remote for MusicCast.app
open "build/Remote for MusicCast.app"
```

You can also open `Package.swift` in Xcode.

Run the app from the `.app` bundle, not with `swift run`. Without the bundle, macOS doesn't show the local network permission prompt, and settings are stored under a different name.

## Checking against a receiver

The binary has two options that print to the terminal instead of opening the UI:

```sh
APP="build/Remote for MusicCast.app/Contents/MacOS/MusicCastRemote"
"$APP" --discover   # list receivers found with SSDP
"$APP" --check      # print status, inputs, presets and a test radio search
```

`--check` doesn't change playback or presets, but it does browse the receiver's radio menu. Run both before and after a change that touches `Client.swift`, `Receiver.swift`, `Discovery.swift` or `RadioBrowser.swift`.

You can also query the receiver directly, which is handy for seeing what a model returns:

```sh
curl http://<receiver-ip>/YamahaExtendedControl/v1/system/getDeviceInfo
curl http://<receiver-ip>/YamahaExtendedControl/v1/main/getStatus
```

If you don't have a MusicCast receiver, you can still work on UI and code that doesn't talk to the receiver. Say in your pull request that you couldn't test against hardware. A mock receiver for testing without hardware would be a welcome contribution.

## Code layout

| File | What it does |
| --- | --- |
| `App.swift` | App entry point, window, menu bar extra and the `--check` / `--discover` options |
| `Client.swift` | Minimal HTTP client for Yamaha Extended Control (YXC) |
| `Receiver.swift` | Receiver state that the UI observes, polling and commands |
| `Discovery.swift` | Finds receivers on the network with SSDP |
| `RadioBrowser.swift` | Net radio search through the receiver's menu |
| `ContentView.swift` | Main window |
| `MenuBarView.swift` | Menu bar extra |
| `ReceiverCommands.swift` | The Receiver menu in the app's menu bar, with keyboard shortcuts |
| `Routines.swift`, `SongHistory.swift` | Saved routines and net radio history |
| `Migration.swift` | Copies settings from when the app was called Yamaha Remote |

## Code style

- Follow the style of the code around your change: 4-space indentation, SwiftUI, no third-party dependencies.
- Use `///` doc comments to say *why* when it isn't obvious from the code.
- Keep changes focused. A pull request that fixes one thing is easier to review than one that also reformats or renames.
- Write user-facing text in sentence case and keep it short.

## Commits and pull requests

1. Fork the repo and create a branch from `main`.
2. Make your change and check it with `./build.sh` and, if you can, against a receiver.
3. Write commit messages as a short imperative sentence describing the change, for example `Add a Low volume preset at -40 dB`. Add a body if the reason isn't obvious.
4. Open a pull request and fill in the template. Add screenshots for visible changes.
5. If your change affects users, add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

## Releases

Maintainers make releases by updating the version in `Info.plist` and `CHANGELOG.md`, then tagging `vX.Y.Z` and attaching the zipped app built with `./build.sh`.
