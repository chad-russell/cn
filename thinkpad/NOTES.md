# Thinkpad Operational Notes

## 2026-05-05: iwlwifi Firmware Crash + Swap Cascade

### What happened

Periodic CPU spikes and multi-second system freezes on the ThinkPad T14s Gen 6 (Intel Core Ultra 7 258V, Lunar Lake). Got progressively worse over 4 days of uptime until the machine became completely unresponsive and required a power-cycle.

### Root cause

**Primary:** Intel integrated WiFi adapter (PCI `8086:a840`, firmware `bz-b0-fm-c0-c101` v101, `iwlmld` driver) has a firmware bug triggered by TCP/Generic Segmentation Offload (TSO/GSO). When active, the firmware's `SYSTEM_STATISTICS_CMD` periodically times out, causing a full adapter reset (`Device error - SW reset`) with massive debug log dumps. Each crash freezes the system for 2-10 seconds. Crashes accelerate over uptime (2 on day 1 → 6 on day 3 → 9+ on day 4).

Same bug documented in [CachyOS/linux-cachyos#673](https://github.com/CachyOS/linux-cachyos/issues/673) on Intel BE401/BE200 hardware with the same firmware family.

**Compounding:** With `vm.swappiness` at the default 60, Ghostty terminal accumulated 13GB in swap over 4 days despite 23GB free RAM. Each WiFi crash triggered I/O stalls paging memory back in, amplifying the freezes.

### Fixes applied

1. **`boot.kernel.sysctl."vm.swappiness" = 10`** — stops long-running apps from drifting to swap
2. **`options iwlwifi power_save=0`** in `boot.extraModprobeConfig` — prevents power-state transition failures
3. **NetworkManager dispatcher script** disables TSO+GSO on `wlp0s20f3` via `ethtool -K` on every interface-up — eliminates the firmware crash trigger

All in `thinkpad/configuration.nix`.

### How to check for recurrence

```bash
# Count WiFi firmware crashes this boot (should be 0)
journalctl -b | grep -c "iwlwifi.*Device error"

# Crash timeline if any
journalctl -b | grep "iwlwifi.*Device error"

# Verify TSO/GSO is off
ethtool -k wlp0s20f3 | grep -E "tcp-segmentation|generic-segmentation"

# Check swap pressure
cat /proc/sys/vm/swappiness
free -h

# Per-process swap usage (look for anything >500MB)
for pid in /proc/[0-9]*/status; do swap=$(grep VmSwap "$pid" 2>/dev/null | awk '{print $2}'); if [ -n "$swap" ] && [ "$swap" -gt 500000 ]; then name=$(grep Name "$pid" | awk '{print $2}'); echo "$swap kB - $name ($(basename $(dirname $pid)))"; fi; done | sort -rn
```

### Also observed (not fixed, minor)

- **164 zombie processes** — `Command Spawner` children of `niri` never reaped, plus old speech-dispatcher children (`sd_voxin`, `sd_baratinoo`, etc.). Consume no CPU/RAM, just process table slots. Niri has a leak here.
