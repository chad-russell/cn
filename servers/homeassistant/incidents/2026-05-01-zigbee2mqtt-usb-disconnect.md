# Incident Report: Zigbee2MQTT USB Disconnect

## Summary

On 2026-05-01, the Sonoff Zigbee 3.0 USB dongle physically disconnected and re-enumerated, causing Zigbee2MQTT to lose its serial connection and enter `error` state. This resulted in a broad device outage affecting 1241 of 1420 entities.

Unlike the 2026-04-14 incident, this was not caused by a serial port mapping error. The Z2M configuration was already using the correct stable by-id path.

## Impact

- Zigbee2MQTT entered `error` state
- 1241 / 1420 entities became `unavailable`
- OTBR and Mosquitto remained `started` throughout
- Z2M bridge connection sensor went `off`

## Detection

User reported Home Assistant showed inability to connect to Zigbee devices.

## Timeline

- `17:50` Sonoff dongle re-enumerated (USB reconnect visible in `/dev/serial/by-id` symlink timestamp)
- `17:50:38` Zigbee herdsman reported `Port closed, error=Error: bad file descriptor`
- `17:50:38` `Fatal error, status=ERROR_SERIAL_INIT`
- `17:50:38` Z2M logged `Adapter disconnected, stopping` and disconnected from MQTT
- Investigation confirmed:
  - Both USB radios present and healthy
  - Z2M configured with correct by-id path (not unstable ttyACM path)
  - OTBR `started` on correct device
  - Mosquitto `started`
- Z2M was restarted via Supervisor
- After restart, Z2M returned to `started` state
- Unavailable entities dropped from 1241 to 4

## Root Cause

The Sonoff Zigbee USB dongle experienced a USB-level disconnect/reconnect event. This caused the open serial file descriptor to become invalid (`bad file descriptor`), which triggered an unrecoverable EZSP error in zigbee-herdsman. Z2M shut down cleanly but did not auto-recover.

Possible underlying causes for the USB disconnect:

- USB hub power fluctuation
- Loose physical connection
- Dongle firmware issue

## Resolution

Restarted Zigbee2MQTT via `ha supervisor apps restart 45df7312_zigbee2mqtt`. The dongle had already re-enumerated at the same by-id path, so Z2M was able to reconnect immediately.

## Prevention

This type of transient USB disconnect cannot be fully prevented by configuration. Possible mitigations:

- Ensure the USB dongle is physically seated securely
- Consider using a USB extension cable to reduce physical stress on the dongle
- Monitor Z2M state and auto-restart on error (Supervisor may already retry, but did not in this case)
- Add the USB disconnect pattern to the health monitoring system on hub
