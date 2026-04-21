# vim: set ft=make :
####################
### custom-apps.just
####################
## Example application installation commands
## These are simplified examples adapted from Bluefin

# Install default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    echo "Installing default applications via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile

# Install development tools via Homebrew
[group('Apps')]
install-dev-tools:
    #!/usr/bin/env bash
    echo "Installing development tools via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile

# Install fonts via Homebrew
[group('Apps')]
install-fonts:
    #!/usr/bin/env bash
    echo "Installing fonts via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile

# Install all Brewfiles at once
[group('Apps')]
install-all-brew:
    #!/usr/bin/env bash
    echo "Installing all applications from Brewfiles..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile

# Install JetBrains Toolbox for managing JetBrains IDEs
[group('Apps')]
install-jetbrains-toolbox:
    #!/usr/bin/env bash
    echo "Installing JetBrains Toolbox..."
    pushd "$(mktemp -d)"
    echo "Fetching latest version..."
    curl -sSfL -o releases.json "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
    BUILD_VERSION=$(jq -r '.TBA[0].build' ./releases.json)
    DOWNLOAD_LINK=$(jq -r '.TBA[0].downloads.linux.link' ./releases.json)
    CHECKSUM_LINK=$(jq -r '.TBA[0].downloads.linux.checksumLink' ./releases.json)
    echo "Installing JetBrains Toolbox ${BUILD_VERSION}"
    curl -sSfL -O "${DOWNLOAD_LINK}"
    curl -sSfL "${CHECKSUM_LINK}" | sha256sum -c
    tar zxf jetbrains-toolbox-"${BUILD_VERSION}".tar.gz
    mkdir -p $HOME/.local/share/JetBrains/ToolboxApp/
    mv jetbrains-toolbox-"${BUILD_VERSION}"/* $HOME/.local/share/JetBrains/ToolboxApp/
    popd
    echo "Launching JetBrains Toolbox..."
    $HOME/.local/share/JetBrains/ToolboxApp/bin/jetbrains-toolbox

# Shortcut for install-jetbrains-toolbox
[group('Apps')]
jetbrains-toolbox:
    @ujust install-jetbrains-toolbox

# Install a Flatpak application from Flathub
[group('Apps')]
install-flatpak APP_ID:
    #!/usr/bin/bash
    echo "Installing {{ APP_ID }} from Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub {{ APP_ID }}

# Example: Install VSCode via Flatpak
[group('Apps')]
install-vscode:
    ujust install-flatpak com.visualstudio.code

# Example: Install GIMP via Flatpak
[group('Apps')]
install-gimp:
    ujust install-flatpak org.gimp.GIMP

[group('Apps')]
install-linear:
    curl --proto '=https' --tlsv1.2 -LsSf https://github.com/schpet/linear-cli/releases/download/v1.9.1/linear-installer.sh | sh

# Enable DankMaterialShell (DMS) integration with niri
[group('Desktop')]
setup-niri-dms:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Enabling DMS for niri session..."
    systemctl --user add-wants niri.service dms
    echo "DMS will now start automatically when you log into niri."
    echo "Log out and log back in to niri for changes to take effect."

# Shortcut for setup-niri-dms
[group('Desktop')]
niri-dms:
    @ujust setup-niri-dms

# Set system to never suspend on idle (keep system awake for SSH/services)
[group('Desktop')]
disable-auto-suspend:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Disabling auto-suspend on idle..."
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
    echo "Done. System will stay awake until you manually run: systemctl suspend"

# Shortcut for disable-auto-suspend
[group('Desktop')]
no-auto-suspend:
    @ujust disable-auto-suspend

# Copy preferred VS Code settings to Cursor
[group('Apps')]
copy-vscode-settings:
    #!/usr/bin/env bash
    set -euo pipefail
    SOURCE_DIR="/home/crussell/Code/cn/vscode"
    TARGET_DIR="$HOME/.config/Cursor/User"

    if [ ! -d "$HOME/.config/Cursor" ]; then
        echo "Error: ~/.config/Cursor directory does not exist."
        echo "Please install and run Cursor first to create the directory."
        exit 1
    fi

    echo "Copying VS Code settings to Cursor..."
    mkdir -p "$TARGET_DIR"
    cp -r "$SOURCE_DIR/keybindings.json" "$TARGET_DIR/"
    cp -r "$SOURCE_DIR/settings.json" "$TARGET_DIR/"
    echo "Settings copied successfully!"


