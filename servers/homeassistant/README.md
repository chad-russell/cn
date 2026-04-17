# Home Assistant on HAOS

Home Assistant runs on a dedicated Home Assistant OS host on the LAN.

## Host Details

- **LAN IP:** `192.168.20.51`
- **OS:** Home Assistant OS 17.2
- **Home Assistant Core:** `2026.4.2` at the time this doc was written
- **Primary URL:** `https://homeassistant.crussell.io`
- **Local URL:** `http://homeassistant.local:8123`

## Operational Model

- Home Assistant Core and Supervisor run on HAOS.
- Add-ons are managed as Supervisor apps.
- The main operational entrypoints are:
  - Home Assistant UI/API over HTTPS
  - Terminal & SSH add-on over SSH on `192.168.20.51:22`

Important distinction:

- SSH lands in the `Advanced SSH & Web Terminal` add-on container, not directly on the HAOS host.
- `ha` commands inside that shell need an explicit Supervisor token when run non-interactively.
- Use `login` from an interactive shell if host-level commands are required.

## SSH Access

The current SSH path is via the `Advanced SSH & Web Terminal` add-on.

- **Host:** `192.168.20.51`
- **Username:** `hassio`
- **Password:** configured in the add-on UI, not stored in this repo

Interactive SSH example:

```bash
ssh hassio@192.168.20.51
```
SSH username: `hassio`
SSH password: `password`

Repo helpers:

```bash
# Open an SSH session
servers/homeassistant/scripts/ha-ssh.sh

# Run Supervisor-backed HA CLI commands remotely
servers/homeassistant/scripts/ha-supervisor.sh apps list --raw-json
```

Environment variables supported by the helper scripts:

- `HA_HAOS_HOST` - defaults to `192.168.20.51`
- `HA_HAOS_USER` - defaults to `hassio`
- `HA_SSH_PASSWORD` - optional; if set, scripts can authenticate non-interactively

## Supervisor CLI From SSH

The SSH add-on container exposes the Supervisor token at:

- `/run/s6/container_environment/SUPERVISOR_TOKEN`

Manual pattern:

```bash
TOKEN=$(cat /run/s6/container_environment/SUPERVISOR_TOKEN)
ha --api-token "$TOKEN" apps list --raw-json
ha --api-token "$TOKEN" apps info core_mosquitto --raw-json
ha --api-token "$TOKEN" apps logs 45df7312_zigbee2mqtt
```

Useful add-on slugs:

- `a0d7b954_ssh` - Advanced SSH & Web Terminal
- `core_mosquitto` - Mosquitto broker
- `45df7312_zigbee2mqtt` - Zigbee2MQTT
- `core_openthread_border_router` - OpenThread Border Router
- `core_matter_server` - Matter Server

## Troubleshooting Workflow

### 1. Confirm the scope of the outage

From an external machine with a Home Assistant long-lived token:

```bash
curl -s "https://homeassistant.crussell.io/api/states" \
  -H "Authorization: Bearer $HA_TOKEN" | \
  jq '{total:length, unavailable:([.[] | select(.state=="unavailable")] | length)}'
```

If needed, use the HA websocket API for richer diagnostics such as:

- `config/entity_registry/list`
- `config_entries/get`
- `repairs/list_issues`
- `system_log/list`

### 2. Check Supervisor app state

```bash
servers/homeassistant/scripts/ha-supervisor.sh apps list --raw-json | jq '.data.addons[] | {slug,state}'
```

For radio-related outages, inspect at least:

- `core_mosquitto`
- `45df7312_zigbee2mqtt`
- `core_openthread_border_router`
- `core_matter_server`

### 3. Check app config and logs

```bash
servers/homeassistant/scripts/ha-supervisor.sh apps info 45df7312_zigbee2mqtt --raw-json
servers/homeassistant/scripts/ha-supervisor.sh apps logs 45df7312_zigbee2mqtt

servers/homeassistant/scripts/ha-supervisor.sh apps info core_openthread_border_router --raw-json
servers/homeassistant/scripts/ha-supervisor.sh apps logs core_openthread_border_router
```

Key indicators:

- MQTT disconnects or repeated reconnects
- Zigbee2MQTT `Failed to start zigbee-herdsman`
- Zigbee2MQTT `HOST_FATAL_ERROR` / `EZSP` startup failures
- OTBR `RCP failure detected`
- Matter loaded but one or more devices still unavailable

### 4. Verify serial devices and stable paths

On the HA shell:

```bash
ls -l /dev/serial/by-id
ls -l /dev/ttyACM*
lsusb
```

Never trust `/dev/ttyACM0` and `/dev/ttyACM1` to stay stable across reboots.

Prefer these stable by-id paths:

- Zigbee coordinator:
  - `/dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_20230605142145-if00`
- Thread RCP:
  - `/dev/serial/by-id/usb-Nabu_Casa_ZBT-2_DCB4D910D158-if00`

### 5. Audit radio port assignments

```bash
servers/homeassistant/scripts/ha-radio-audit.sh
```

This checks for:

- unstable `/dev/ttyACM*` or `/dev/ttyUSB*` paths
- Zigbee2MQTT and OTBR using the same device
- Zigbee2MQTT pointed at the ZBT-2
- OTBR pointed at the Sonoff coordinator

## Known Pitfalls

- Public Home Assistant REST auth does not grant direct access to Supervisor endpoints such as `/api/hassio/*`.
- Non-interactive `ha` CLI calls from the SSH add-on return `unauthorized` unless `--api-token "$SUPERVISOR_TOKEN"` is passed explicitly.
- The web terminal has limited scrollback, so long logs are easier to inspect over SSH.
- `binary_sensor.zigbee2mqtt_bridge_connection_state` reflects whether the Zigbee2MQTT bridge is online in MQTT and is a useful quick health signal.

## Radio Configuration Rules

- Use `/dev/serial/by-id/...` for all serial radios.
- Do not configure Zigbee2MQTT or OTBR to use `/dev/ttyACM0`, `/dev/ttyACM1`, `/dev/ttyUSB0`, or `/dev/ttyUSB1`.
- Keep Zigbee2MQTT on the Sonoff coordinator.
- Keep OTBR on the ZBT-2.

This prevents the specific reboot-induced port renumbering failure documented in `incidents/2026-04-14-zigbee-thread-serial-port-collision.md`.

## Related Files

- `servers/homeassistant/incidents/2026-04-14-zigbee-thread-serial-port-collision.md`
- `servers/homeassistant/scripts/ha-ssh.sh`
- `servers/homeassistant/scripts/ha-supervisor.sh`
- `servers/homeassistant/scripts/ha-radio-audit.sh`
