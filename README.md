# One-click Audio Converter for Plasma

This repo contains a KDE service menu installer that adds a Dolphin context
menu entry for batch audio conversion. When invoked it launches a Zenity UI
where you can pick the target format (OGG, MP3, WMA), choose a quality preset,
and monitor progress for all selected files at once.

## Features

- Installs `one-click-audio-converter.desktop` for Plasma 5/6 service menus.
- Deploys the runner script to `~/.local/bin/one-click-audio-converter`.
- Uses Zenity for format/quality selection, progress bar, and result dialogs.
- Converts multiple files via FFmpeg, auto-resolving name collisions.
- Optionally installs `ffmpeg` and `zenity` through `pkexec` + `apt-get` if
  they are missing.

## Requirements

- KDE Dolphin with service menus allowed (`shell_access=true`).
- `ffmpeg` compiled with `libvorbis`, `libmp3lame`, and `wmav2`.
- `zenity`.
- `pkexec` and `apt-get` (only if you rely on the installer to fetch deps).

## Installation

```bash
chmod +x install-service-menu.sh          # first run only
./install-service-menu.sh --force
```

The script auto-detects Plasma 5 vs 6; override with `--plasma5`, `--plasma6`,
or `--target-dir DIR` as needed. Use `--force` to replace an existing service
menu entry.

## Usage

1. In Dolphin, select one or more audio files.
2. Right-click → `One-click Conversion → Convert audio...`.
3. Choose the destination format/quality in the Zenity dialog and confirm.
4. Wait for the progress bar to finish; a final dialog summarizes success or
   lists any files that failed to convert.

Output files are written alongside the originals. If the destination name is
already taken, the runner appends ` (1)`, ` (2)`, etc.

## Troubleshooting

- If the menu does not appear, restart Dolphin and confirm that
  `shell_access=true` in `~/.config/kdeglobals`.
- Zenity errors typically mean the dependency is missing—rerun the installer
  or install `zenity` manually.
- Conversion failures will show up in the final dialog; run the runner from a
  terminal to see the raw FFmpeg error output for deeper debugging.
