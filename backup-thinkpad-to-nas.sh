#!/usr/bin/env bash
# =============================================================================
# ThinkPad → NAS Pre-NixOS Backup
# 
# Uses tar over ssh (no rsync needed on either side).
# Target: root@192.168.20.31:/mnt/tank/backups/thinkpad-pre-nixos/
#
# Run: bash backup-thinkpad-to-nixos.sh
# Then: sudo bash -c 'cd / && tar cf - etc/nebula | ssh root@192.168.20.31 "mkdir -p /mnt/tank/backups/thinkpad-pre-nixos/system && tar xf - -C /mnt/tank/backups/thinkpad-pre-nixos/system"'
# =============================================================================

set -euo pipefail

NAS="root@192.168.20.31"
BASE="/mnt/tank/backups/thinkpad-pre-nixos"
HOME="/home/crussell"

CODE_EXCLUDES=(
    --exclude='target'
    --exclude='node_modules'
    --exclude='.next'
    --exclude='dist'
    --exclude='.turbo'
    --exclude='__pycache__'
    --exclude='.pnpm-store'
)

echo "============================================"
echo " ThinkPad Pre-NixOS Backup"
echo " Target: ${NAS}:${BASE}"
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
echo ">>> Pre-flight..."
ssh -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 "${NAS}" "echo 'NAS reachable' && mkdir -p '${BASE}'" || {
    echo "ERROR: Cannot reach NAS"
    exit 1
}
echo ""

# ---------------------------------------------------------------------------
# Helper: tar a local dir → extract on NAS
# ---------------------------------------------------------------------------
send_dir() {
    local src="$1"
    local dest="$2"
    shift 2

    local basename
    basename="$(basename "${src}")"
    local parent
    parent="$(dirname "${src}")"

    echo "  -> ${dest}  (${basename})"
    ssh -i ~/.ssh/id_ed25519 "${NAS}" "mkdir -p '${BASE}/${dest}'"
    tar cf - -C "${parent}" "$@" "${basename}" | ssh -i ~/.ssh/id_ed25519 "${NAS}" "tar xf - -C '${BASE}/${dest}'"
}

# ---------------------------------------------------------------------------
# Phase 1: Critical credentials and dotfiles
# ---------------------------------------------------------------------------
echo ">>> Phase 1: Critical credentials and dotfiles"

# SSH keys
send_dir "${HOME}/.ssh"        "dotfiles"
# Age key (needed to decrypt repo secrets!)
send_dir "${HOME}/.config/age" "dotfiles"
# GPG
send_dir "${HOME}/.gnupg"      "dotfiles"
# PKI
send_dir "${HOME}/.pki"        "dotfiles"
send_dir "${HOME}/.certs"      "dotfiles"

# Shell rc files (individual files, not symlinks)
echo "  -> dotfiles/shell-rc"
ssh -i ~/.ssh/id_ed25519 "${NAS}" "mkdir -p '${BASE}/dotfiles/shell-rc'"
for f in .bashrc .bash_profile .bash_history .zshrc .zprofile .profile \
         .gitconfig .gitconfig.bak-1775143773 .wget-hsts .python_history .duckdb_history; do
    src="${HOME}/${f}"
    if [ -f "${src}" ] && [ ! -L "${src}" ]; then
        tar cf - -C "${HOME}" "${f}" | ssh -i ~/.ssh/id_ed25519 "${NAS}" "tar xf - -C '${BASE}/dotfiles/shell-rc'"
    elif [ -f "${src}" ]; then
        echo "     (skipping symlink: ${f})"
    fi
done

echo ""

# ---------------------------------------------------------------------------
# Phase 2: Code repositories
# ---------------------------------------------------------------------------
echo ">>> Phase 2: Code repositories (excluding build artifacts & .pnpm-store)"

send_dir "${HOME}/Code"     "Code"     "${CODE_EXCLUDES[@]}"
send_dir "${HOME}/Gloo"     "Gloo"     "${CODE_EXCLUDES[@]}"
send_dir "${HOME}/Projects" "Projects"

echo ""

# ---------------------------------------------------------------------------
# Phase 3: Personal files
# ---------------------------------------------------------------------------
echo ">>> Phase 3: Personal files"

send_dir "${HOME}/Documents" "Personal"
send_dir "${HOME}/Pictures"  "Personal"
send_dir "${HOME}/Desktop"   "Personal"

echo ""

# ---------------------------------------------------------------------------
# Phase 4: Application configs and AI tool data
# ---------------------------------------------------------------------------
echo ">>> Phase 4: App configs and tool data"

send_dir "${HOME}/.config" "dotfiles" \
    --exclude='cache' \
    --exclude='chromium' \
    --exclude='google-chrome' \
    --exclude='libreoffice'

send_dir "${HOME}/.agents"     "dotfiles"
send_dir "${HOME}/.claude"     "dotfiles"
send_dir "${HOME}/.codex"      "dotfiles"
send_dir "${HOME}/.gemini"     "dotfiles"
send_dir "${HOME}/.cursor"     "dotfiles"
send_dir "${HOME}/.pi"         "dotfiles"
send_dir "${HOME}/.mcp-auth"   "dotfiles"
send_dir "${HOME}/.modern"     "dotfiles"
send_dir "${HOME}/.arbor"      "dotfiles"
send_dir "${HOME}/.justx"      "dotfiles"
send_dir "${HOME}/.railway"    "dotfiles"
send_dir "${HOME}/.wd40"       "dotfiles"
send_dir "${HOME}/.plannotator" "dotfiles"
send_dir "${HOME}/.vim"        "dotfiles"

echo ""

# ---------------------------------------------------------------------------
# Phase 5: Flatpak app data
# ---------------------------------------------------------------------------
echo ">>> Phase 5: Flatpak app data (Slack, BambuStudio, Bottles)"

send_dir "${HOME}/.var/app/com.slack.Slack"          "flatpak-data"
send_dir "${HOME}/.var/app/com.bambulab.BambuStudio" "flatpak-data"
send_dir "${HOME}/.var/app/com.usebottles.bottles"   "flatpak-data"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================================"
echo " Backup complete!"
echo ""
echo " Verify on NAS:"
echo "   ssh -i ~/.ssh/id_ed25519 ${NAS} du -sh '${BASE}'/* | sort -rh"
echo ""
echo " TODO (run manually for /etc/nebula):"
echo "   sudo tar cf - -C / etc/nebula | ssh -i ~/.ssh/id_ed25519 ${NAS} \"tar xf - -C '${BASE}/system'\""
echo ""
echo " SKIPPED (regenerable):"
echo "   ~/Downloads/      (5.1G)"
echo "   ~/.bun/           (8.7G)"
echo "   ~/.rustup/        (9G)"
echo "   ~/.cache/         (16G)"
echo "   ~/.cargo/"
echo "   ~/.local/share/brioche/ (34G)"
echo "   ~/.local/state/brunch/  (12G)"
echo "   ~/.npm/ ~/.conda/ ~/.ollama/ (1.9G) ~/.wine/ (1.7G)"
echo "   build artifacts   (target/, node_modules/, .next/, .pnpm-store)"
echo "   Chrome, Zoom, Zen, Firefox, Telegram flatpak data"
echo ""
echo " CRITICAL to restore first on NixOS:"
echo "   ~/.ssh/           - SSH keys"
echo "   ~/.config/age/    - age key (needed for repo secrets!)"
echo "   ~/.gnupg/         - GPG keys"
echo "============================================"
