#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ha_supervisor="$script_dir/ha-supervisor.sh"

z2m_json="$($ha_supervisor apps info 45df7312_zigbee2mqtt --raw-json)"
otbr_json="$($ha_supervisor apps info core_openthread_border_router --raw-json)"

z2m_state="$(jq -r '.data.state' <<<"$z2m_json")"
z2m_adapter="$(jq -r '.data.options.serial.adapter // ""' <<<"$z2m_json")"
z2m_port="$(jq -r '.data.options.serial.port // ""' <<<"$z2m_json")"

otbr_state="$(jq -r '.data.state' <<<"$otbr_json")"
otbr_port="$(jq -r '.data.options.device // ""' <<<"$otbr_json")"

echo "Zigbee2MQTT"
echo "  state:   $z2m_state"
echo "  adapter: $z2m_adapter"
echo "  port:    $z2m_port"
echo
echo "OpenThread Border Router"
echo "  state:   $otbr_state"
echo "  device:  $otbr_port"
echo

warnings=0

if [[ "$z2m_port" =~ ^/dev/tty(ACM|USB) ]]; then
  echo "WARN: Zigbee2MQTT is using an unstable tty path: $z2m_port" >&2
  warnings=1
fi

if [[ "$otbr_port" =~ ^/dev/tty(ACM|USB) ]]; then
  echo "WARN: OTBR is using an unstable tty path: $otbr_port" >&2
  warnings=1
fi

if [[ -n "$z2m_port" && "$z2m_port" == "$otbr_port" ]]; then
  echo "WARN: Zigbee2MQTT and OTBR are configured to use the same serial device" >&2
  warnings=1
fi

if [[ "$z2m_port" == *"Nabu_Casa_ZBT-2"* ]]; then
  echo "WARN: Zigbee2MQTT appears to be pointed at the ZBT-2 radio" >&2
  warnings=1
fi

if [[ "$otbr_port" == *"SONOFF_Zigbee_3.0"* ]]; then
  echo "WARN: OTBR appears to be pointed at the Sonoff Zigbee coordinator" >&2
  warnings=1
fi

if [[ "$warnings" -eq 0 ]]; then
  echo "Radio assignment audit passed."
  exit 0
fi

exit 1
