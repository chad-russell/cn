# Date Night

A tiny web app to track and randomly pick restaurants for date night. Dark speakeasy-themed UI with a slot-machine picker.

## Features

- Restaurants organized by category: Breakfast, Lunch, Pizza, Indian
- Full CRUD: add, rename, delete any restaurant
- Mark restaurants as visited or back onto the list
- "Spin the Wheel" random picker with a fun cycling animation
- All data persisted to `restaurants.json`

## Quick Start (Local)

```bash
cd servers/hub/apps/datenight
pip install -r requirements.txt
DATA_FILE=restaurants.json python app.py
# Open http://localhost:7890
```

## Podman Deployment

```bash
# Build
podman build -t datenight .

# Create persistent data directory
mkdir -p ~/srv/datenight/data
cp restaurants.json ~/srv/datenight/data/

# Run
podman run -d --name datenight \
  -p 7890:7890 \
  -v ~/srv/datenight/data:/data:Z \
  -e DATA_FILE=/data/restaurants.json \
  datenight
```

## Quadlet (systemd)

```bash
# Copy the hub-managed quadlet
cp servers/hub/quadlets/containers/datenight.container ~/.config/containers/systemd/

# Ensure data dir exists
sudo mkdir -p /srv/datenight/data
sudo cp servers/hub/apps/datenight/restaurants.json /srv/datenight/data/

# Reload and start
systemctl --user daemon-reload
systemctl --user start datenight
```

The application source lives in `servers/hub/apps/datenight/`.
The host deployment quadlet lives in `servers/hub/quadlets/containers/datenight.container`.

## Adding a Caddy Route

Add to your Caddyfile:

```
datenight.internal.crussell.io {
    reverse_proxy localhost:7890
}
```

Then reload: `sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile`
