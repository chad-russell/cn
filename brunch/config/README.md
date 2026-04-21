# Brunch Config Layout

This directory contains the Brunch configuration used by this repository.

## Targets

Named targets are exported from `brunch.bri`:

- `ai`
- `hub`
- `thinkpad`

Apply one explicitly:

```bash
brunch apply ./config --target ai
brunch apply ./config --target hub
brunch apply ./config --target thinkpad
```

There is no default export. `--target` is required by the CLI.

## Layout

- `features/`: reusable leaf modules that usually export a single `brunchConfig`
- `profiles/`: shared merged layers composed from features
- `hosts/<name>/`: final machine-oriented targets and host-only helpers
- `brunch.bri`: target registry
- `project.bri`: Brioche project entrypoint and named target re-exports

## Current Structure

- `profiles/common.bri`: shared shell, editor, agent, and Pi config
- `profiles/desktop-base.bri`: desktop baseline for graphical workstation targets
- `hosts/ai/index.bri`: AI host target composition
- `hosts/hub/index.bri`: hub target composition
- `hosts/thinkpad/index.bri`: thinkpad target composition

## Placement Rules

Use `features/` for small reusable building blocks.

Examples:

- `features/nvim.bri`
- `features/pi.bri`

Use `profiles/` for shared merged layers that are reused by multiple hosts.

Use `hosts/` for final host assembly and host-only helpers, scripts, and managed assets.

Examples:

- `hosts/hub/dev-stacks.bri`
- `hosts/hub/backup.bri`
- `hosts/hub/backup/`
- `hosts/ai/index.bri`

## Flatpaks

Flatpaks are managed declaratively in `flatpaks/brunch.bri`.

They are installed and reconciled on `brunch apply`.

## Related Docs

- Generic Brunch tool and API docs: [`../README.md`](../README.md)
- Root repo navigation: [`../../AGENTS.md`](../../AGENTS.md)
