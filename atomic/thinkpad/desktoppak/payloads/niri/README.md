# Niri desktoppak payload

This directory contains the current Niri session payload for desktoppak.

## Purpose

It defines the image and default config for a self-contained Niri session that
runs under the generic desktoppak runtime.

## Files

```text
payloads/niri/
├── Containerfile
├── build.sh
├── manifest.json
├── niri-config.kdl
└── vicinae-settings.json
```

Related generic pieces live outside this directory:

- `../../cli/desktoppak.py`
- `../../runtime/launch-bwrap-session.sh`
- `../../runtime/desktoppak-session.sh`
- `../../runtime/desktoppak-spawn.sh`
- `../../docs/manifest-v1.md`
- `../../docs/manifest-v1.schema.json`

## Build

```bash
cd desktoppak/payloads/niri
./build.sh
```

Default image ref:

```text
localhost/niri-session:dev
```

## Install / update

```bash
python3 desktoppak/cli/desktoppak.py install niri localhost/niri-session:dev
python3 desktoppak/cli/desktoppak.py update niri
```

## Register with GDM

```bash
python3 desktoppak/cli/desktoppak.py register niri --dm gdm
```

## Runtime behavior

- compositor runs inside the desktoppak sandbox
- host apps launch via `desktoppak-spawn` -> `flatpak-spawn --host`
- companion tools like Noctalia and Vicinae live in the payload image
- persistent config/state live under `~/.local/share/desktoppak/niri/`

## Logs

```text
~/.local/share/desktoppak/niri/state/session/logs/session.log
~/.local/share/desktoppak/niri/state/session/logs/desktoppak-spawn.log
```

## Config refresh

Seeded config is copied on first run. To force a fresh copy from the repo:

```bash
rm -f ~/.local/share/desktoppak/niri/config/niri/config.kdl
rm -f ~/.local/share/desktoppak/niri/config/vicinae/settings.json
```
