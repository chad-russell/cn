# Opencode NixOS Module

A self-contained module for opencode configuration with Antigravity plugin support.

## Structure
```
modules/opencode/
├── config/
│   ├── package.json          (Dependencies)
│   ├── opencode.json       (Google models + plugins)
│   └── oh-my-opencode.json (Agent models)
└── default.nix                  (Module definition + setup script)
```

## How to Use

### 1. Rebuild Configuration
After changing this module, rebuild your configuration:
```bash
home-manager switch --flake ~/Code/cn#think
```

### 2. Use opencode
```bash
opencode auth login
# Select "Google" (not "antigravity")
# Complete OAuth flow in browser
```

### 3. Run with Google Models
```bash
opencode run "Hello" --model=google/antigravity-claude-sonnet-4.5-thinking --variant=max
```

## What's Included

- Google provider with Antigravity models (Gemini 3, Claude 4.5 thinking)
- Antigravity plugin with OAuth authentication (browser-based login)
- Automatic plugin installation and patching on activation
- Oh-my-opencode integration with Google models configured
- Self-contained setup - everything is managed by Nix/Home Manager

## Notes

- **Important**: When running `opencode auth login`, search for **"Google"** in the provider list, not "antigravity". The plugin registers itself under the `google` provider ID.
- The plugin patch adds a `default` export to ensure `opencode` can load the plugin correctly.
- Plugin version: `opencode-antigravity-auth@1.2.9-beta.2`
