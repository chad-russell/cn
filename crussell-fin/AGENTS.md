# Copilot Instructions for crussell-fin bootc Image

Personal Fedora Atomic workstation image based on finpilot/Bluefin. Built and deployed locally via Justfile commands.

## Build & Deploy Workflow

This image is built and deployed **locally only** - no CI/CD infrastructure.

### Key Commands

| Command | Purpose |
|---------|---------|
| `just build` | Build container image with podman |
| `just switch` | Build unique timestamped image and queue bootc switch |
| `just build-qcow2` | Build QCOW2 VM image for testing |
| `just run-vm-qcow2` | Run VM from QCOW2 image |

### Switch Workflow

`just switch` performs:
1. Generates unique tag: `stable-YYYYMMDD-HHMMSS`
2. Builds image with `just build`
3. Loads image into rootful podman
4. Runs `bootc switch` to queue the new image
5. Reboot with `sudo systemctl reboot` to apply

## Pre-Commit Checklist

1. **Conventional Commits** - All commits MUST follow `<type>: <description>` format
2. **Shellcheck** - Run `just lint` on modified shell files
3. **Justfile syntax** - Run `just --list` to verify
4. **Confirm with user** - Always confirm before committing

## Repository Structure

```
├── Containerfile          # Main build definition (multi-stage build)
├── Justfile               # Build automation (build, switch, VM commands)
├── build/                 # Build-time scripts
│   ├── 10-build.sh       # Main build script (packages, services)
│   └── *.sh.example      # Example scripts (rename to use)
├── custom/                # Runtime customizations
│   ├── brew/             # Homebrew Brewfiles (CLI tools)
│   ├── flatpaks/         # Flatpak preinstall (GUI apps)
│   └── ujust/            # User commands
├── iso/                   # ISO/disk image configs
│   ├── disk.toml         # VM image config (QCOW2/RAW)
│   └── iso.toml          # ISO installer config
└── .pre-commit-config.yaml # Pre-commit hooks (optional)
```

## Core Principles

### Build-time vs Runtime

- **Build-time** (`build/`): Baked into container. Use `dnf5 install`. Services, configs, system packages.
- **Runtime** (`custom/`): User installs after deployment. Brewfiles, Flatpaks. CLI tools, GUI apps.

### Bluefin Convention Compliance

- Use `dnf5` exclusively (never `dnf`, `yum`, `rpm-ostree`)
- Always `-y` flag for non-interactive
- COPRs: enable → install → **DISABLE**
- Numbered scripts: `10-build.sh`, `20-*.sh`, `30-*.sh`

## Where to Add Packages

### System Packages (Build-time)

**Location**: `build/10-build.sh`

```bash
dnf5 install -y vim git htop
```

Use for: system utilities, services, dependencies needed at boot.

### Homebrew Packages (Runtime)

**Location**: `custom/brew/*.Brewfile`

```ruby
brew "bat"
brew "eza"
brew "ripgrep"
```

Use for: CLI tools, dev environments. Users install via `ujust` commands.

### Flatpak Applications (Runtime)

**Location**: `custom/flatpaks/*.preinstall`

```ini
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable
```

Use for: GUI apps. Installed post-first-boot.

## Quick Reference

| Request | Action | Location |
|---------|--------|----------|
| Add system package | `dnf5 install -y pkg` | `build/10-build.sh` |
| Add CLI tool | `brew "pkg"` | `custom/brew/default.Brewfile` |
| Add GUI app | `[Flatpak Preinstall org.app.id]` | `custom/flatpaks/default.preinstall` |
| Add user command | Create shortcut | `custom/ujust/*.just` |
| Test locally | `just build && just build-qcow2 && just run-vm-qcow2` | |
| Deploy | `just switch && sudo systemctl reboot` | |

## Common Patterns

### Adding Third-Party Repos

```bash
# Add repo, install, cleanup
cat > /etc/yum.repos.d/google-chrome.repo << 'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

dnf5 install -y google-chrome-stable
rm -f /etc/yum.repos.d/google-chrome.repo
```

### Using COPR

```bash
dnf5 copr enable -y user/repo
dnf5 install -y package-name
dnf5 copr disable -y user/repo
```

### Enabling Services

```bash
systemctl enable podman.socket
systemctl mask unwanted-service
```

## Multi-Stage Build Architecture

The Containerfile uses multi-stage builds following @projectbluefin/distroless:

**Stage 1 (ctx)**: Combines local build scripts with OCI container resources
**Stage 2**: Runs build scripts from base image

Build scripts access resources at `/ctx/`:
- Local scripts: `/ctx/build/`
- Custom files: `/ctx/custom/`
- OCI resources: `/ctx/oci/`

## Image Tags

Local builds use:
- `crussell-fin:stable` - Default tag
- `crussell-fin:stable-YYYYMMDD-HHMMSS` - Unique timestamp (for switch)

## Debugging

### Build Issues

```bash
# Verbose build
podman build --log-level=debug .

# Check script syntax
shellcheck build/*.sh

# Validate justfile
just --list
```

### Runtime Issues

```bash
bootc status
systemctl list-units --failed
journalctl -b -p err
ujust --list
```

## Critical Rules

1. Use Conventional Commits format
2. Never use `dnf5` in ujust files
3. Always disable COPRs after use
4. Use `dnf5` exclusively with `-y` flag
5. Run shellcheck before committing

## Resources

- **Bluefin patterns**: https://github.com/ublue-os/bluefin
- **bootc documentation**: https://github.com/containers/bootc
- **Conventional Commits**: https://www.conventionalcommits.org/
- **Flatpak IDs**: https://flathub.org/
- **Homebrew**: https://brew.sh/
- **Justfile**: https://just.systems/

---

**Last Updated**: 2025-03-02
