# Contributing to Midpoint

Thanks for helping out! Bug reports, ideas, and pull requests are all welcome.

## Reporting bugs

Open an [issue](https://github.com/akhilmadipalli/midpoint/issues/new/choose) using the bug report form.
The most useful things to include:

- Your macOS version and trackpad (built-in, Magic Trackpad, Magic Trackpad 2…)
- What you did, what you expected, and what happened
- The last ~20 lines of the debug log: menu bar icon → **Settings…** → **Open Debug Log**

## Development setup

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). There's no
Xcode project; everything builds with one script.

```sh
git clone https://github.com/akhilmadipalli/midpoint.git
cd midpoint
./build.sh --install     # build for your Mac and install to /Applications
```

| Path | What it is |
| --- | --- |
| `Sources/main.swift` | Engine: multitouch input, tap detection, event tap, settings |
| `Sources/UI.swift` | Menu bar item and settings window |
| `build.sh` | Build, install (`--install`), and package releases (`--release`) |
| `scripts/install.sh` | The `curl \| bash` installer |
| `tools/mtprobe.swift` | Prints raw multitouch frames; handy for debugging input |
| `tools/make-icon.swift` | Regenerates `Resources/AppIcon.icns` |

**Accessibility permission while developing:** if you have an Apple Development certificate, `build.sh`
signs with it and macOS remembers the permission across rebuilds. Without one, builds are signed ad-hoc and
you need to remove and re-add Midpoint in Privacy & Security → Accessibility after each rebuild.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Keep changes focused; one feature or fix per PR.
3. Match the existing style: plain AppKit, no third-party dependencies, comments that explain *why*.
4. Test on a real trackpad. Mention what you tested in the PR description.
5. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for user-visible changes.

CI builds every pull request for both Apple silicon and Intel; it needs to pass before merging.

## Releasing (maintainers)

1. Update `VERSION` and move the **Unreleased** changelog entries under a new version heading.
2. Commit, then tag and push: `git tag v$(cat VERSION) && git push origin main --tags`.
3. The Release workflow builds and publishes the `.zip`, `.dmg`, and `SHA256SUMS`.
4. Update the Homebrew cask: `scripts/update-cask.sh` (prints the new version and checksum for
   [homebrew-tap](https://github.com/akhilmadipalli/homebrew-tap)).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating you agree to uphold it.
