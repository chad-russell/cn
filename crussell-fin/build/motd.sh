#!/usr/bin/env bash

# Custom MOTD (Message of the Day) Script
# Replaces the default ublue-motd to avoid dependencies on missing files (glow, image-info.json)
# Provides useful system information without external dependencies

set -euo pipefail

if [ -t 1 ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m'
    readonly BOLD='\033[1m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly NC=''
    readonly BOLD=''
fi

get_terminal_width() {
    if command -v tput >/dev/null 2>&1; then
        tput cols 2>/dev/null || echo 80
    else
        echo 80
    fi
}

print_separator() {
    local width=$(get_terminal_width)
    printf "${CYAN}%*s${NC}\n" "$width" | tr ' ' '='
}

get_hostname() {
    hostname 2>/dev/null || echo "unknown"
}

get_uptime() {
    if command -v uptime >/dev/null 2>&1; then
        uptime -p 2>/dev/null || uptime -s 2>/dev/null || echo "unknown"
    else
        if [ -f /proc/uptime ]; then
            local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
            local days=$((uptime_seconds / 86400))
            local hours=$((uptime_seconds / 3600 % 24))
            echo "$days days, $hours hours"
        else
            echo "unknown"
        fi
    fi
}

get_kernel() {
    uname -r 2>/dev/null || echo "unknown"
}

get_architecture() {
    uname -m 2>/dev/null || echo "unknown"
}

get_shell() {
    echo "$SHELL" | xargs basename 2>/dev/null || echo "unknown"
}

get_load_avg() {
    if [ -f /proc/loadavg ]; then
        awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || echo "N/A"
    elif command -v uptime >/dev/null 2>&1; then
        uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo "N/A"
    else
        echo "N/A"
    fi
}

get_memory_info() {
    if [ -f /proc/meminfo ]; then
        local mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        local mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || awk '/MemFree/ {print $2}' /proc/meminfo)
        local total_gb=$((mem_total / 1024 / 1024))
        local avail_gb=$((mem_avail / 1024 / 1024))
        echo "${avail_gb}GB / ${total_gb}GB"
    else
        echo "N/A"
    fi
}

print_welcome() {
    local hostname=$(get_hostname)
    printf "\n"
    printf "${BOLD}${GREEN}Welcome to ${hostname}${NC}\n"
    printf "${CYAN}A custom bootc-based operating system${NC}\n"
}
print_system_info() {
    print_separator
    printf "${BOLD}${BLUE}System Information${NC}\n"
    print_separator

    printf "  ${YELLOW}Uptime:${NC}        %s\n" "$(get_uptime)"
    printf "  ${YELLOW}Kernel:${NC}        %s\n" "$(get_kernel)"
    printf "  ${YELLOW}Architecture:${NC}  %s\n" "$(get_architecture)"
    printf "  ${YELLOW}Shell:${NC}         %s\n" "$(get_shell)"
    printf "  ${YELLOW}Memory:${NC}        %s\n" "$(get_memory_info)"
    printf "  ${YELLOW}Load Average:${NC}  %s\n" "$(get_load_avg)"
}
print_helpful_commands() {
    print_separator
    printf "${BOLD}${BLUE}Quick Reference${NC}\n"
    print_separator

    printf "  ${CYAN}ujust${NC}            - List available custom commands\n"
    printf "  ${CYAN}brew help${NC}        - Get help with Homebrew\n"
    printf "  ${CYAN}flatpak list${NC}     - List installed Flatpak apps\n"

    if [ -x "$(command -v bootc)" ]; then
        printf "  ${CYAN}bootc status${NC}     - Check bootc status\n"
        printf "  ${CYAN}bootc upgrade${NC}    - Update the system\n"
    fi
}
print_update_reminder() {
    print_separator
    if [ -x "$(command -v bootc)" ]; then
        printf "${YELLOW}System updates: run 'bootc upgrade' to check for updates${NC}\n"
    else
        printf "${YELLOW}System updates: check your package manager for updates${NC}\n"
    fi
}
main() {
    print_welcome
    printf "\n"
    print_system_info
    printf "\n"
    print_helpful_commands
    printf "\n"
    print_update_reminder
    print_separator
    printf "\n"
}
main
