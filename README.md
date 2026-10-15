<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Midpoint icon">
</p>

<h1 align="center">Midpoint</h1>

<p align="center">Middle click on your Mac trackpad: a three-finger click or a three-finger tap.</p>

<p align="center">
  <a href="https://github.com/akhilmadipalli/midpoint/releases/latest"><img src="https://img.shields.io/github/v/release/akhilmadipalli/midpoint" alt="Latest release"></a>
  <a href="https://github.com/akhilmadipalli/midpoint/actions/workflows/ci.yml"><img src="https://github.com/akhilmadipalli/midpoint/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/akhilmadipalli/midpoint" alt="MIT license"></a>
</p>

---

Midpoint is a small, free, open-source menu bar app for macOS. With it you can open links in background
tabs, close browser tabs, paste in Terminal, or pan in CAD apps without a mouse.

- **Three-finger click:** press the trackpad with three fingers and get a middle click. Holding and dragging gives a middle-button drag.
- **Three-finger tap:** a light three-finger tap also sends a middle click.
- **Menu bar status:** the icon dims when Midpoint isn't active, and a live status window shows the finger count and the last click.
- **Lightweight:** about 500 lines of Swift, no dependencies, no network access, no analytics.

## Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel)
- Built-in or Magic Trackpad

## Install

Pick whichever you like; they all install the same app to `/Applications`.

**Homebrew**

```sh
brew install --cask akhilmadipalli/tap/midpoint
```

**curl**

```sh
curl -fsSL https://raw.githubusercontent.com/akhilmadipalli/midpoint/main/scripts/install.sh | bash
```

The script downloads the latest release, verifies its SHA-256 checksum, installs it, and opens it.
Set `MIDPOINT_VERSION=0.3.0` to pin a version or `MIDPOINT_APPDIR=~/Applications` to install elsewhere.

**DMG**

Download [**Midpoint.dmg**](https://github.com/akhilmadipalli/midpoint/releases/latest/download/Midpoint.dmg)
(or the `.zip`) from the [latest release](https://github.com/akhilmadipalli/midpoint/releases/latest),
open it, and drag Midpoint to Applications.

> Midpoint isn't notarized by Apple yet, so the first time you open a downloaded copy macOS says it
> "cannot verify" the app. Click **Done**, then go to **System Settings → Privacy & Security**, scroll down and
> click **Open Anyway**. (Homebrew and the curl script skip this step.)

**Build from source**

Needs Xcode or the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/akhilmadipalli/midpoint.git
cd midpoint
./build.sh --install
open /Applications/Midpoint.app
```

### Grant Accessibility access

On first launch macOS asks for **Accessibility** access, which Midpoint needs to send middle clicks.
Turn Midpoint on in **System Settings → Privacy & Security → Accessibility**. It starts working
within a second; no relaunch needed.

After updating to a new version, if middle clicks stop working, turn Midpoint off and on again in that list.

## Usage

Click the menu bar icon to switch gestures on or off, enable **Launch on Login**, or open **Settings…**.
If you hide the menu bar icon, open Midpoint from Finder or Spotlight to get the settings window back.

### Conflicts with macOS gestures

macOS has its own uses for three fingers. Turn these off in **System Settings → Trackpad**:

- **Look up & data detectors → Tap with three fingers.** This competes with three-finger tap.
- **Accessibility → Pointer Control → Trackpad Options → Use trackpad for dragging → Three Finger Drag.**
  When this is on, macOS treats a three-finger tap as a click.

## How it works

1. **Touch input.** Midpoint reads raw contact frames from Apple's private `MultitouchSupport` framework,
   so it always knows how many fingers are on the trackpad.
2. **Three-finger click.** A session-level `CGEventTap` intercepts left-mouse events. If three fingers are down
   when the trackpad is pressed, the event is rewritten in place to the middle button (`otherMouseDown/Dragged/Up`,
   button 2) before any app sees it.
3. **Three-finger tap.** When all fingers lift, Midpoint checks the touch session: exactly three fingers,
   shorter than 0.35 s, almost no movement, and no physical click. If all hold, it posts a middle click
   at the cursor.

Everything is in [`Sources/main.swift`](Sources/main.swift) (engine) and [`Sources/UI.swift`](Sources/UI.swift)
(menu bar item and settings window).

> `MultitouchSupport` is a private Apple framework. It has been stable for years, but a future macOS update
> could break Midpoint.

## Troubleshooting

- **Nothing happens:** open **Settings…** from the menu bar.
  - If **Fingers on trackpad** stays at 0 while you touch the trackpad, touch input isn't arriving.
  - If the finger count works but **Last middle click** never changes, check the gesture conflicts above.
- **Debug log:** Settings → **Open Debug Log** (`~/Library/Logs/Midpoint.log`). Each touch session is logged
  with finger count, duration, movement, and whether it counted as a tap.
- **Raw touch probe:** `swiftc -O -o build/mtprobe tools/mtprobe.swift && build/mtprobe 15` prints raw
  multitouch frames for 15 seconds.

## Uninstall

- **Homebrew:** `brew uninstall --cask --zap midpoint`
- **Anything else:** `curl -fsSL https://raw.githubusercontent.com/akhilmadipalli/midpoint/main/scripts/install.sh | bash -s -- --uninstall`,
  or quit Midpoint, delete `/Applications/Midpoint.app`, and remove it from Privacy & Security → Accessibility.

## Contributing

Bug reports, ideas, and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started, and
please follow the [code of conduct](CODE_OF_CONDUCT.md). Security issues: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
