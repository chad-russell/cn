#!/usr/bin/env bash
set -euo pipefail

echo "=== Checking CLI tools ==="
for cmd in podman git; do
    if command -v "$cmd" &>/dev/null; then
        echo "  ✓ $cmd"
    else
        echo "  ✗ $cmd (missing)"
    fi
done

# Check pnpm
if command -v pnpm &>/dev/null || [ -x "$HOME/.local/bin/pnpm" ]; then
    echo "  ✓ pnpm"
else
    echo "  ✗ pnpm (missing — run: npm install -g --prefix ~/.local pnpm)"
fi

# Check bun
if command -v bun &>/dev/null; then
    echo "  ✓ bun"
else
    echo "  ✗ bun (missing — needed for Buildspace)"
fi

# Check Node 24 for Polymer
if [ -x "/home/linuxbrew/.linuxbrew/opt/node@24/bin/node" ]; then
    echo "  ✓ node@24 (Homebrew, for Polymer)"
else
    echo "  ✗ node@24 (missing — run: brew install node@24)"
fi

# Check age for secrets
if command -v age &>/dev/null || [ -x "/home/linuxbrew/.linuxbrew/bin/age" ]; then
    echo "  ✓ age"
else
    echo "  ✗ age (missing — run: brew install age)"
fi

echo ""
echo "=== Checking Gloo prerequisites ==="
for path in \
    "$HOME/Gloo/360-gpl" \
    "$HOME/Gloo/360-hummingbird" \
    "$HOME/Gloo/360-polymer"; do
    if [ -d "$path" ]; then
        echo "  ✓ $path"
    else
        echo "  ✗ $path (missing)"
    fi
done

if [ -f "$HOME/.config/age/key.txt" ]; then
    echo "  ✓ age key"
else
    echo "  ✗ age key (missing — needed to decrypt dev secrets)"
fi

echo ""
echo "=== Checking Buildspace prerequisites ==="
if [ -d "$HOME/Code/bs/buildspace" ]; then
    echo "  ✓ $HOME/Code/bs/buildspace"
else
    echo "  ✗ $HOME/Code/bs/buildspace (missing)"
fi

for envfile in \
    "$HOME/Code/bs/buildspace/.env"; do
    if [ -f "$envfile" ]; then
        echo "  ✓ $envfile"
    else
        echo "  ✗ $envfile (missing)"
    fi
done
