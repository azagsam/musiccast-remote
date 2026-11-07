# Remote for MusicCast

A small macOS app for controlling a Yamaha MusicCast receiver over the local network, using Yamaha Extended Control (YXC). Built and tested with an R-N602.

> [!NOTE]
> This is an unofficial, independent project. It is not affiliated with, endorsed by or supported by Yamaha Corporation in any way. See [Trademarks](#trademarks).

<p align="center">
  <img src="docs/screenshots/main-window.png" width="390" alt="Main window: now playing with artwork and audio format, volume presets, inputs and station list">
  &nbsp;&nbsp;
  <img src="docs/screenshots/menu-bar.png" width="292" alt="Menu bar extra: current station, routine, volume and presets">
</p>

- Power, volume in dB (slider, typed value, or Quiet / Low / Medium / Loud presets), mute
- Inputs, net radio and tuner presets, internet radio search
- Now playing with artwork and the incoming audio format
- Song history for net radio
- Routines: one click turns the receiver on, plays a preset and sets the volume
- A menu bar extra that keeps working with the window closed

## Requirements

- macOS 13 Ventura or later, on an Apple silicon or Intel Mac
- A Yamaha MusicCast receiver on the same network as the Mac

## Tested receivers

| Model | Result |
| --- | --- |
| R-N602 | Everything works |

Have a different MusicCast device? Please [report how it works](https://github.com/azagsam/musiccast-remote/issues/new?template=receiver_report.yml), even if everything works. See [#1](https://github.com/azagsam/musiccast-remote/issues/1).

## Install

1. Download `Remote-for-MusicCast-<version>.zip` from the [latest release](https://github.com/azagsam/musiccast-remote/releases/latest) and unzip it.
2. Move **Remote for MusicCast.app** to your Applications folder.
3. Open it. The app isn't notarized by Apple, so macOS blocks it the first time:
   - **macOS 15 Sequoia and later:** click **Done**, then go to System Settings ▸ Privacy & Security, scroll down and click **Open Anyway**.
   - **macOS 13 and 14:** right-click the app, choose **Open**, then click **Open** again.

   Or remove the quarantine flag in Terminal, then open the app normally:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Remote for MusicCast.app"
   ```

On first launch, macOS asks whether Remote for MusicCast may find devices on your local network. Choose **Allow**, or the app can't reach the receiver. If you declined, turn it on in System Settings ▸ Privacy & Security ▸ Local Network.

The app looks for receivers with SSDP when it starts. If it doesn't find yours, click the receiver name at the top of the window and enter its IP address.

To start the app at login, add it in System Settings ▸ General ▸ Login Items.

To update, quit the app, download the new release and replace the copy in Applications.

## Build from source

You need the Xcode Command Line Tools with Swift 5.9 or later. Full Xcode isn't needed. Install the tools with:

```sh
xcode-select --install
```

Then build:

```sh
git clone https://github.com/azagsam/musiccast-remote.git
cd musiccast-remote
./build.sh
cp -R "build/Remote for MusicCast.app" /Applications/
```

`build.sh` builds a universal binary with `swift build` and packages it as `build/Remote for MusicCast.app`, signed ad hoc. A copy you built yourself opens without the Gatekeeper steps above.

To update, quit the app, then `git pull`, run `./build.sh` and copy the app again.

## Command line checks

The binary has two options that don't open the UI:

```sh
"build/Remote for MusicCast.app/Contents/MacOS/MusicCastRemote" --discover   # list receivers on the network
"build/Remote for MusicCast.app/Contents/MacOS/MusicCastRemote" --check      # print status, presets and a test search
```

`--check` doesn't change playback or presets, but it does browse the receiver's radio menu.

## Data

Settings are kept in the app's user defaults (`io.github.azagsam.MusicCastRemote`). The song history and routines are in `~/Library/Application Support/Remote for MusicCast/`.
Settings and data from versions named Yamaha Remote are copied over on first launch.

## Contributing

Contributions are welcome, especially reports from receiver models other than the R-N602. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started, and the [changelog](CHANGELOG.md) for what's new.

## License

[MIT](LICENSE)

## Trademarks

This is an independent project, not affiliated with, endorsed by or sponsored by Yamaha Corporation. Yamaha and MusicCast are trademarks of Yamaha Corporation, used here only to describe which devices the app works with.
