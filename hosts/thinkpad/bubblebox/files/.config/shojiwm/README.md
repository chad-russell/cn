# ShojiWM user config (repo-managed)

This is `~/.config/shojiwm` — the TypeScript/TSX config for the **ShojiWM**
session (the second compositor, Containerfile step 2.8; Umbriel + DMS were
retired 2026-11). It is ShojiWM's default config (`packages/config/` from the
pinned commit), seeded from `/usr/share/shojiwm/default-config/` on first
setup and repo-managed here like `~/.config/nvim`. `node_modules/shoji_wm` is
NOT in the repo: setup symlinks it to `/usr/lib/shojiwm/packages/shoji_wm`,
the runtime tree the compositor's config API resolves against (the Deno/V8
engine is embedded in the binary — no Node install needed). Edit freely and
press `Super+Shift+R` in the session to hot-reload; `dev/preview.sh` runs it
nested for iterating without leaving niri. The session's shell is
**shoji-bar-4** (`~/.config/shoji-bar-4`, a user-side Rust build — see the
thinkpad README), which this config launches if its binary is present.
