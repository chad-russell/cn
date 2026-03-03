# vim: set ft=make :
#######################
### server-commands.just
#######################
## Server-specific commands for container and service management

# Show status of all containers
[group('Containers')]
ps:
    podman ps -a

# Show container logs (requires container name)
[group('Containers')]
logs name:
    podman logs -f {{ name }}

# Start a container stack with podman-compose
[group('Containers')]
up path=".":
    #!/usr/bin/env bash
    cd {{ path }}
    podman-compose up -d

# Stop a container stack
[group('Containers')]
down path=".":
    #!/usr/bin/env bash
    cd {{ path }}
    podman-compose down

# Restart a container
[group('Containers')]
restart name:
    podman restart {{ name }}

# Show container resource usage
[group('Containers')]
top:
    podman top -l

# List all container images
[group('Containers')]
images:
    podman images

# Prune unused containers and images
[group('Maintenance')]
prune:
    #!/usr/bin/env bash
    echo "Pruning unused containers, images, and volumes..."
    podman system prune -af
    podman volume prune -f
    echo "Done!"

# Show disk usage
[group('System')]
disk-usage:
    #!/usr/bin/env bash
    echo "=== Container Storage ==="
    podman system df
    echo ""
    echo "=== Disk Usage ==="
    df -h

# Show memory usage
[group('System')]
mem-usage:
    free -h

# Show listening ports
[group('System')]
ports:
    ss -tulpn

# Quick backup with restic (requires restic configured)
[group('Backup')]
backup:
    #!/usr/bin/env bash
    if ! command -v restic &>/dev/null; then
        echo "restic not installed"
        exit 1
    fi
    echo "Run: restic backup <paths>"
    echo "Ensure RESTIC_REPOSITORY and RESTIC_PASSWORD are set"

# Update system and reboot if needed
[group('Maintenance')]
update:
    #!/usr/bin/env bash
    echo "Updating system..."
    sudo bootc upgrade
    echo "Reboot with: sudo systemctl reboot"

# Show recent journal logs
[group('System')]
journal lines="100":
    journalctl -n {{ lines }} --no-pager

# Follow journal logs
[group('System')]
journal-follow:
    journalctl -f

# Install server tools via Homebrew
[group('Setup')]
install-server-tools:
    #!/usr/bin/env bash
    echo "Installing server tools via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/server.Brewfile

# Configure firewall for common services
[group('Setup')]
configure-firewall:
    #!/usr/bin/env bash
    echo "Configuring firewall..."
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --permanent --add-service=http
    sudo firewall-cmd --permanent --add-service=https
    sudo firewall-cmd --reload
    echo "Firewall configured for ssh, http, https"

# Show system info
[group('System')]
info:
    #!/usr/bin/env bash
    echo "=== Hostname ==="
    hostname
    echo ""
    echo "=== Kernel ==="
    uname -a
    echo ""
    echo "=== CPU ==="
    lscpu | grep -E "^Model name|^CPU\(s\)|^CPU MHz"
    echo ""
    echo "=== Memory ==="
    free -h | head -2
    echo ""
    echo "=== Uptime ==="
    uptime
