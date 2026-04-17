# Incident Report: Zigbee and Thread Radio Port Collision

## Summary

On 2026-04-14, Home Assistant experienced a broad device outage after reboot. The major impact was loss of Zigbee2MQTT-managed devices, with additional Thread/Matter instability.

The root cause was a serial device mapping mismatch: Zigbee2MQTT was configured to use `/dev/ttyACM0`, but after reboot the Sonoff Zigbee coordinator came up as `/dev/ttyACM1` while the ZBT-2 Thread radio came up as `/dev/ttyACM0`.

That caused Zigbee2MQTT and OTBR to contend for the same ZBT-2 radio.

## Impact

- Home Assistant remained up.
- `1193 / 1360` entities became `unavailable`.
- `1178` unavailable entities were tied to the `mqtt` config entry used by Zigbee2MQTT discovery.
- OTBR entered `setup_retry` with `Unable to connect`.
- Matter stayed loaded, but the Yale front door lock was unavailable.

## Detection

Initial symptom from the UI:

- `Home Assistant Connect ZBT-2 (OpenThread Border Router): Failed setup, will retry: Unable to connect`

Additional evidence gathered during troubleshooting:

- Home Assistant system log showed `Error returned from MQTT server: The connection was lost.`
- Zigbee2MQTT bridge connection sensor was `off`.
- Zigbee2MQTT add-on state was `error`.
- OTBR add-on state was `error`.

## Timeline

Approximate timeline based on Supervisor and add-on logs:

- `10:15` OTBR reported `RCP failure detected` and exited.
- `10:18` Zigbee2MQTT opened the serial port but repeatedly failed EZSP startup.
- `10:18-10:32` Zigbee2MQTT restarted several times and failed with `HOST_FATAL_ERROR`.
- Investigation showed:
  - Sonoff by-id path -> `/dev/ttyACM1`
  - ZBT-2 by-id path -> `/dev/ttyACM0`
  - Zigbee2MQTT config still pointed at `/dev/ttyACM0`
- `11:01` Zigbee2MQTT config was corrected to the Sonoff by-id path and both add-ons were restarted.
- After recovery, unavailable entities dropped from `1193` to `16`.

## Root Cause

Zigbee2MQTT used an unstable Linux serial path:

- configured path: `/dev/ttyACM0`

After reboot, Linux assigned the devices as:

- ZBT-2 -> `/dev/ttyACM0`
- Sonoff Zigbee dongle -> `/dev/ttyACM1`

OTBR was already correctly configured to the ZBT-2 by-id path, so both Zigbee2MQTT and OTBR tried to use the ZBT-2 radio.

## Contributing Factors

- Zigbee2MQTT was configured with `/dev/ttyACM0` instead of a by-id path.
- Both radios were present and healthy at the USB layer, which made the problem look like a generic radio failure until add-on config was inspected.
- The Home Assistant web terminal has limited scrollback, which slowed direct log inspection.
- Supervisor APIs are not directly available through the public Home Assistant URL with a standard long-lived token.

## What We Did

1. Verified Home Assistant was up and counted unavailable entities through the HA API.
2. Used the HA websocket API to correlate unavailable entities to config entries.
3. Confirmed the outage was dominated by MQTT/Zigbee2MQTT entities.
4. Established SSH access through the `Advanced SSH & Web Terminal` add-on.
5. Retrieved the Supervisor token from `/run/s6/container_environment/SUPERVISOR_TOKEN`.
6. Queried Supervisor app info and logs for:
   - `core_mosquitto`
   - `45df7312_zigbee2mqtt`
   - `core_openthread_border_router`
7. Verified actual radio mappings under `/dev/serial/by-id`.
8. Found Zigbee2MQTT configured to `/dev/ttyACM0` instead of the Sonoff by-id path.
9. Updated Zigbee2MQTT to:
   - `/dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_20230605142145-if00`
10. Restarted:
   - `45df7312_zigbee2mqtt`
   - `core_openthread_border_router`
11. Verified:
   - Zigbee2MQTT state `started`
   - OTBR state `started`
   - HA unavailable entities reduced to `16`

## Resolution

The incident was resolved by moving Zigbee2MQTT from an unstable `/dev/ttyACM0` assignment to the Sonoff's stable `/dev/serial/by-id/...` path, then restarting Zigbee2MQTT and OTBR.

## Prevention

The exact failure mode that triggered this incident is now prevented:

- Zigbee2MQTT no longer depends on `/dev/ttyACM0`
- OTBR and Zigbee2MQTT now use distinct stable by-id device paths

This does not prevent every possible future Zigbee/Thread outage. It specifically prevents the reboot-induced serial renumbering and radio collision that caused this incident.

Recommended standing rules:

- use `/dev/serial/by-id/...` for all HA serial radios
- audit radio assignments after hardware changes or firmware flashing
- keep a reusable SSH and Supervisor workflow for pulling logs quickly

## Follow-Up Artifacts

- Host guide: `servers/homeassistant/README.md`
- SSH helper: `servers/homeassistant/scripts/ha-ssh.sh`
- Supervisor helper: `servers/homeassistant/scripts/ha-supervisor.sh`
- Radio audit helper: `servers/homeassistant/scripts/ha-radio-audit.sh`
