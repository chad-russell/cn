# Hub Dev Stacks

This directory documents the Brunch-managed dev stacks that are meant to run on `hub`.

Current hub target includes:

- shared dev infra
- Buildspace
- Gloo local dev stacks

## Preflight

Run this before applying the `hub` Brunch target:

```bash
./servers/hub/dev-stacks/preflight.sh
```

It checks for:

- `brunch`, `brioche`, and `podman`
- required local repo clones
- required env files

## Apply

From the repo root on `hub`:

```bash
brunch apply ./brunch/config --target hub
```

## Start Stacks

```bash
systemctl --user start buildspace.service
systemctl --user start gloo-gpl.service
systemctl --user start gloo-polymer.service
systemctl --user start gloo-admin.service
```

Start everything:

```bash
systemctl --user start gloo-all.service
```
