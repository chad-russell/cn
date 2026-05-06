### Remaining items to address when you're home (not urgent):

 1. Podman IPv6 on k2 — the fd32:... IPv6 addresses in the logs are noisy but didn't
 actually block relay in this case. You may want to disable IPv6 on Podman networks to
 clean up the logs.
 2. Stale certs for bees (10.10.0.5) and phone (10.10.0.11) — these are spamming the
 Hetzner logs with "could not find ca for the certificate". They need certs re-signed by
 the current CA.
 3. The manual /etc/nebula/config.yaml on the thinkpad is a leftover from before the
 NixOS module managed it — harmless but could be confusing later.
