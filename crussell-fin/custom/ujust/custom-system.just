# vim: set ft=make :
#######################
### custom-system.just
#######################
## Example system configuration commands
## These are simplified examples adapted from Bluefin

# Run a system benchmark (requires stress-ng from Homebrew)
[group('System')]
benchmark:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    if ! type -P "stress-ng" &>/dev/null ; then
        echo "stress-ng is not installed."
        if command -v brew &>/dev/null; then
            if gum confirm "Install stress-ng via Homebrew?" ; then
                brew install stress-ng
                brew link stress-ng
            else
                exit 0
            fi
        else
            echo "Please install stress-ng to run benchmarks."
            exit 1
        fi
    fi
    echo 'Running a 1 minute benchmark...'
    pushd $(mktemp -d) > /dev/null
    stress-ng --matrix 0 -t 1m --times
    popd > /dev/null

# Configure docker and libvirt groups for development
[group('System')]
configure-dev-groups:
    #!/usr/bin/pkexec bash
    CURRENT_USER="{{ `id -un` }}"
    echo "Adding $CURRENT_USER to docker and libvirt groups..."

    # Ensure groups exist in /etc/group
    for group in docker libvirt; do
        if ! grep -q "^$group:" /etc/group; then
            echo "Adding $group to /etc/group"
            grep "^$group:" /usr/lib/group | tee -a /etc/group > /dev/null
        fi
        usermod -aG $group $CURRENT_USER
    done

    echo "Groups configured. Log out and back in for changes to take effect."

# Example toggle command with user choice
[group('System')]
toggle-example-feature:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "This is an example toggle command."
    echo "Current status: [check your status here]"
    OPTION=$(Choose "Enable" "Disable" "Cancel")
    case "$OPTION" in
        "Enable")
            echo "Enabling feature..."
            # Add your enable logic here
            ;;
        "Disable")
            echo "Disabling feature..."
            # Add your disable logic here
            ;;
        "Cancel")
            echo "No changes made."
            ;;
    esac

# Clean up container images and volumes
[group('Maintenance')]
clean-containers:
    #!/usr/bin/bash
    echo "Cleaning up Podman containers, images, and volumes..."
    podman system prune -af
    podman volume prune -f
    echo "Cleanup complete!"

# Update system and reboot if needed
[group('Maintenance')]
update-and-reboot:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "Updating system..."
    sudo bootc upgrade
    if gum confirm "Reboot now to apply updates?"; then
        systemctl reboot
    else
        echo "Reboot later to apply updates."
    fi

# Set Zen Browser as default system browser
[group('System')]
set-default-browser:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Setting Zen Browser as default browser..."
    xdg-settings set default-web-browser app.zen_browser.zen.desktop
    CURRENT=$(xdg-settings get default-web-browser)
    echo "Default browser set to: $CURRENT"

# Swap caps and escape on GNOME Desktop
[group('System')]
swap-caps-escape-gnome:
    #!/usr/bin/env bash
    gsettings set org.gnome.desktop.input-sources xkb-options "['caps:swapescape']"

# Configure "1570 A" WiFi network DNS (primary: 192.168.20.32, fallback: Google/Cloudflare)
[group('Network')]
setup-1570a-dns:
    #!/usr/bin/pkexec bash
    set -euo pipefail
    SSID="1570 A"
    PRIMARY_DNS="192.168.20.32"
    FALLBACK_DNS="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1"

    echo "Configuring DNS for network: $SSID"
    echo "Primary DNS: $PRIMARY_DNS"
    echo "Fallback DNS: $FALLBACK_DNS (Google + Cloudflare)"
    echo

    nmcli connection modify "$SSID" \
        ipv4.dns "$PRIMARY_DNS $FALLBACK_DNS" \
        ipv4.ignore-auto-dns yes \
        ipv4.method auto

    echo
    echo "Configuration complete! Network $SSID DNS configured."
    echo "Disconnect and reconnect to $SSID to apply changes."
