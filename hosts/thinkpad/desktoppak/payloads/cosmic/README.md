# COSMIC desktoppak payload

Initial desktoppak packaging attempt for COSMIC, derived from the older
container experiment in `../../../cosmic/`.

## Files

```text
payloads/cosmic/
├── Containerfile
├── build.sh
├── manifest.json
└── README.md
```

## Build

```bash
cd desktoppak/payloads/cosmic
./build.sh
```

Default image ref:

```text
localhost/cosmic-session:dev
```

## Install / update

```bash
python3 desktoppak/cli/desktoppak.py install cosmic localhost/cosmic-session:dev
python3 desktoppak/cli/desktoppak.py update cosmic
```

## Register with GDM

```bash
python3 desktoppak/cli/desktoppak.py register cosmic --dm gdm
```

## Notes

- This payload uses `/usr/bin/cosmic-session` as its session entrypoint.
- It assumes the desktoppak runtime's logind-based session model rather than
  the old container experiment's `seatd`-based approach.
- No seeded COSMIC config is included yet.
- This is an initial port, not yet validated at runtime.
