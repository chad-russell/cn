{ config, pkgs, ... }:

{
  # Enable hardware watchdog for automatic reboot on system hang
  boot.kernelModules = [ "iTCO_wdt" ];  # Intel TCO watchdog (common on Intel systems)
  systemd.watchdog.runtimeTime = "30s";  # Systemd will ping watchdog every 15s (half of 30s)
  systemd.watchdog.rebootTime = "2min";  # If systemd fails to respond, reboot after 2 minutes
}

