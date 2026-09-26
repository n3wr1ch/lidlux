# LidLux {{VERSION}}

## Requirements

- Apple Silicon MacBook running macOS 13 or later.
- A DDC/CI-compatible monitor for external display brightness control.

## Install

With Homebrew: `brew install --cask n3wr1ch/tap/lidlux` (or `brew upgrade --cask lidlux`).

Manually:

1. Download `LidLux-{{VERSION}}.zip` below and unzip it.
2. Move `LidLux.app` to `/Applications`.
3. Open LidLux. It uses ad-hoc signing and is **not Developer ID signed or notarized**. If macOS blocks the first launch, open **System Settings → Privacy & Security → Open Anyway** and confirm.

Alternatively, after downloading from this repository and verifying the checksum, remove the quarantine attribute and open the app again:

```sh
xattr -dr com.apple.quarantine /Applications/LidLux.app
```

Brightness key control requires **System Settings → Privacy & Security → Accessibility** permission for LidLux. After an update, you may need to remove the old LidLux entry and add the updated app again because its ad-hoc signature changes.

## Verify the download

Download both the ZIP and its `.sha256` file into the same folder. In Terminal, change to that folder and run:

```sh
shasum -a 256 -c LidLux-{{VERSION}}.zip.sha256
```

The result should be `LidLux-{{VERSION}}.zip: OK`.

