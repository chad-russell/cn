# bubblebox entrypoints (thinkpad)
#
# Source of truth for runnable units. Each entrypoint names a primary package
# and a sandbox spec (binds / env). Copied into the bubblebox store
# ($BUBBLEBOX_DATA_DIR/entrypoints/) by the `cjust link` recipe; `bubblebox run`
# reads from the store copy.
#
# Tools with no special sandbox needs (rg, fd, bat, dust, eza, htop, tokei) do
# NOT need a TOML here — `bubblebox run <name>` synthesizes a default
# { primary = <name> } when no TOML is present. Only tools with binds/env
# ship a TOML.
#
# Schema (see bubblebox/PLAN.md):
#   primary              = "pkg-name"
#   compose              = ["pkg", ...]   # Phase 2 only; default = [primary]
#   [sandbox]
#     writable_home      = bool            # /home rw (default ro)
#     writable_run       = bool            # /run rw (default ro)
#     dirs               = ["/dev/dri", ..]# bwrap --dir targets
#     [[sandbox.bind]]   src=, dst=, mode=(ro|rw|dev|dev-bind), create=bool
#     [[sandbox.bind_try]] ...            # conditional (skipped if src absent)
#     [sandbox.env]      KEY = "val"       # $VAR expanded
#
# `create = true` on a bind mkdir's its (expanded) src before bwrap, so a
# required state-dir bind (e.g. $BUBBLEBOX_DATA_DIR/<pkg> -> /persist) doesn't
# need a pre-run mkdir step.
