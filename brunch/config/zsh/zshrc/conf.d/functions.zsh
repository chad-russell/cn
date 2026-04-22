# Custom functions

# Create directory and change to it
function mkcd {
  mkdir -p $1;
  cd $1;
}

# Kill process listening on a port
function killport {
  lsof -ti:$1 | xargs kill -9
}

# Show what's listening on a port
function whichport {
  lsof -i :$1
}

function cjust_swap_caps_escape_gnome {
    gsettings set org.gnome.desktop.input-sources xkb-options "['caps:swapescape']"
}

function cjust_setup_1570a_dns {
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
}
