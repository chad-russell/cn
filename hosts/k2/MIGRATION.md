# Caddy + Nebula Migration: hub → k2

## Context

We are migrating the last services off `hub` (Fedora Atomic, 192.168.20.105) so it can be wiped and reinstalled with NixOS. The remaining services are:

1. **Caddy** — system-level Podman container that terminates TLS for all `*.internal.crussell.io` and `*.crussell.io` domains. Uses a custom image (`caddy-route53`) with a Route53 DNS plugin for ACME certs. Public traffic flows: Internet → Hetzner VPS (nginx stream proxy) → `10.10.0.6:443` → Caddy.
2. **Nebula host identity** (`10.10.0.6`) — the services endpoint that Hetzner and all internal clients target.
3. **Nebula local lighthouse** (`10.10.0.1`) — discovery-only instance on UDP 4243 that helps roaming clients find peers on the LAN.

All three are moving to **k2** (NixOS, 192.168.20.62). k2 already runs ntfy, SearXNG, and datenight as native NixOS services.

The NixOS config for k2 has already been updated and builds successfully. The k2 config includes:
- Nebula host instance using `10.10.0.6` certs, with `staticHostMap` pointing `10.10.0.1` at `127.0.0.1:4243` and `192.168.20.62:4243`
- Nebula lighthouse instance (`10.10.0.1`) on port 4243 with `tun.disable = true`
- Podman + Caddy quadlet
- Firewall open for 80, 443, 4242/udp, 4243/udp

The `nebula-client.nix` shared module has been updated to point `10.10.0.1` at `192.168.20.62:4243` (instead of the old `192.168.20.105:4243`), but this change has NOT been deployed to k1/k3/k4 yet — that happens after cutover.

## Machine Reference

| Host | LAN IP | SSH | Notes |
|------|--------|-----|-------|
| hub | 192.168.20.105 | `crussell@192.168.20.105` (user), `root@192.168.20.105` (system) | Fedora Atomic, being decommissioned |
| k2 | 192.168.20.62 | `root@192.168.20.62` | NixOS, target for migration |
| k1 | 192.168.20.61 | `root@192.168.20.61` | NixOS, needs nebula client update |
| k3 | 192.168.20.63 | `root@192.168.20.63` | NixOS, needs nebula client update |
| k4 | 192.168.20.64 | `root@192.168.20.64` | NixOS, needs nebula client update |
| Hetzner | 178.156.171.212 | `root@178.156.171.212` | Public VPS, nginx stream proxy → `10.10.0.6:443` |

All SSH uses `-o IdentitiesOnly=yes` when piping data to avoid agent issues. Username is `crussell` for hub user-level access, `root` for everything else.

The repo is at `/home/crussell/Code/cn` on both this machine and hub.

## Migration Steps

### Step 1: Deploy k2 NixOS config

This writes the quadlet file, firewall rules, nebula config, and podman setup to k2. The nebula and caddy services will fail to start because certs/image aren't in place yet — that's expected and fine.

```bash
cd /home/crussell/Code/cn
nix run .#deploy -- k2
```

Verify the deploy succeeded (exit code 0). Expect warnings about `nebula-homelab` and `nebula-lighthouse` failing — that's OK.

After deploy, verify:
- `ssh root@192.168.20.62 "systemctl status nebula-homelab"` — should show failed (no certs)
- `ssh root@192.168.20.62 "podman info"` — should show podman working
- `ssh root@192.168.20.62 "ls /etc/containers/systemd/caddy.container"` — quadlet should exist

### Step 2: Copy nebula certs from hub to k2

Hub has two sets of nebula certs:

**Host identity (10.10.0.6):** Lives at `/etc/nebula/` on hub. Files: `ca.crt`, `host.crt`, `host.key`.

**Local lighthouse (10.10.0.1):** Lives at `/etc/nebula-lh/` on hub. Files: `ca.crt`, `host.crt`, `host.key`.

k2's nebula-host instance expects certs at `/etc/nebula/` and the lighthouse expects certs at `/etc/nebula-lh/`.

```bash
# Copy host identity certs (10.10.0.6)
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo cat /etc/nebula/ca.crt" | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/nebula/ca.crt"
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo cat /etc/nebula/host.crt" | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/nebula/host.crt"
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo cat /etc/nebula/host.key" | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/nebula/host.key"

# Copy lighthouse certs (10.10.0.1)
ssh -o IdentitiesOnly=yes root@192.168.20.62 "mkdir -p /etc/nebula-lh"
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo cat /etc/nebula-lh/ca.crt" | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/nebula-lh/ca.crt"
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo cat /etc/nebula-lh/host.crt" | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/nebula-lh/host.crt"
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo cat /etc/nebula-lh/host.key" | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/nebula-lh/host.key"
```

After copy, verify certs are readable by nebula:
```bash
ssh root@192.168.20.62 "ls -la /etc/nebula/ /etc/nebula-lh/"
```

The NixOS `tmpfiles.rules` in the k2 config should fix permissions on activation, but if nebula still can't read them, run:
```bash
ssh root@192.168.20.62 "chmod 440 /etc/nebula/*.crt /etc/nebula/*.key /etc/nebula-lh/*.crt /etc/nebula-lh/*.key && chown root:nebula-homelab /etc/nebula/host.crt /etc/nebula/host.key /etc/nebula/ca.crt && chown root:nebula-lighthouse /etc/nebula-lh/host.crt /etc/nebula-lh/host.key /etc/nebula-lh/ca.crt"
```

### Step 3: Copy Caddy image, config, and TLS volumes from hub to k2

**3a: Container image**

The `caddy-route53` image is a custom build (Caddy + Route53 DNS plugin). It only exists on hub as a local Podman image.

```bash
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo podman save localhost/caddy-route53:latest" | ssh -o IdentitiesOnly=yes root@192.168.20.62 "podman load"
```

Verify:
```bash
ssh root@192.168.20.62 "podman images localhost/caddy-route53"
```

**3b: Caddy config files**

The Caddy config lives in the repo at `hosts/k2/caddy/`. It needs to be placed at `/etc/caddy/` on k2 for the quadlet to mount it.

```bash
# The Caddyfile
ssh -o IdentitiesOnly=yes root@192.168.20.62 "mkdir -p /etc/caddy"
cat /home/crussell/Code/cn/hosts/k2/caddy/Caddyfile | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/caddy/Caddyfile"

# Routes directory
ssh -o IdentitiesOnly=yes root@192.168.20.62 "mkdir -p /etc/caddy/routes/internal"
for f in /home/crussell/Code/cn/hosts/k2/caddy/routes/internal/*.caddy; do
  echo "Copying $(basename $f)..."
  cat "$f" | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/caddy/routes/internal/$(basename $f)"
done

# AWS credentials for Route53 DNS challenge
cat /home/crussell/Code/cn/hosts/k2/caddy/aws.env | ssh -o IdentitiesOnly=yes root@192.168.20.62 "cat > /etc/caddy/aws.env && chmod 600 /etc/caddy/aws.env"
```

Verify:
```bash
ssh root@192.168.20.62 "ls -la /etc/caddy/ && ls -la /etc/caddy/routes/internal/"
```

**3c: TLS certificate volumes**

Caddy stores its TLS certs and state in two named Podman volumes: `caddy_data` and `caddy_config`. These MUST be migrated so Caddy doesn't need to re-issue all certs (which would cause extended downtime waiting for DNS propagation).

```bash
# Create volumes on k2 (if not already created by activation script)
ssh -o IdentitiesOnly=yes root@192.168.20.62 "podman volume create caddy_data 2>/dev/null; podman volume create caddy_config 2>/dev/null"

# Copy caddy_data (TLS certs — critical)
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo tar -C /var/lib/containers/storage/volumes/caddy_data/_data -cf - ." | ssh -o IdentitiesOnly=yes root@192.168.20.62 "tar -C /var/lib/containers/storage/volumes/caddy_data/_data -xf -"

# Copy caddy_config (Caddy internal state)
ssh -o IdentitiesOnly=yes root@192.168.20.105 "sudo tar -C /var/lib/containers/storage/volumes/caddy_config/_data -cf - ." | ssh -o IdentitiesOnly=yes root@192.168.20.62 "tar -C /var/lib/containers/storage/volumes/caddy_config/_data -xf -"
```

Verify:
```bash
ssh root@192.168.20.62 "ls /var/lib/containers/storage/volumes/caddy_data/_data/ && ls /var/lib/containers/storage/volumes/caddy_config/_data/"
```

You should see directories like `certificates/`, `caddy/`, etc.

### Step 4: Cutover

This is the brief downtime window (~30 seconds). We stop hub's services, then start k2's.

**IMPORTANT:** Do these in order. Do NOT start k2's nebula before stopping hub's, or both will claim `10.10.0.6` and cause conflicts.

```bash
# 4a: Stop hub's services
ssh -o IdentitiesOnly=yes root@192.168.20.105 "
  sudo systemctl stop caddy &&
  sudo systemctl stop nebula &&
  sudo systemctl stop nebula-lh-local &&
  echo 'Hub services stopped'
"

# Verify hub's nebula is down (should show NO nebula0 interface)
ssh -o IdentitiesOnly=yes root@192.168.20.105 "ip addr show nebula0" 2>/dev/null
# Expected: Device "nebula0" does not exist (or error)

# 4b: Start k2's services
ssh -o IdentitiesOnly=yes root@192.168.20.62 "
  systemctl restart nebula-homelab &&
  sleep 2 &&
  systemctl restart nebula-lighthouse &&
  systemctl daemon-reload &&
  systemctl restart caddy &&
  echo 'K2 services started'
"
```

### Step 5: Verify

**5a: Nebula**

```bash
# k2 should now have 10.10.0.6
ssh root@192.168.20.62 "ip addr show nebula.homelab" 2>/dev/null | grep inet
# Expected: inet 10.10.0.6/24

# k2 lighthouse should be listening on 4243
ssh root@192.168.20.62 "ss -ulnp | grep 4243"

# Can k2 reach the Hetzner lighthouse?
ssh root@192.168.20.62 "ping -c 2 10.10.0.2"
```

**5b: Caddy**

```bash
# Direct hit on k2
curl -s -o /dev/null -w "%{http_code}" http://192.168.20.62:443/ 2>/dev/null || echo "HTTPS expected, try:"
curl -sk -o /dev/null -w "%{http_code}" https://192.168.20.62/ 2>/dev/null

# Via public domain (goes through Hetzner → 10.10.0.6)
curl -s https://ntfy.internal.crussell.io/v1/health
# Expected: HTTP 200

curl -s -o /dev/null -w "%{http_code}" https://searxng.internal.crussell.io/
# Expected: 200

curl -s https://datenight.crussell.io/ | head -3
# Expected: HTML content (Date Night app)

curl -s -o /dev/null -w "%{http_code}" https://jellyfin.crussell.io/
# Expected: 200
```

**5c: Check Caddy container logs if anything fails**

```bash
ssh root@192.168.20.62 "podman logs systemd-caddy --tail 30 2>&1"
```

### Step 6: Deploy updated nebula-client to k1, k3, k4

The `nebula-client.nix` module has been updated to point `10.10.0.1` at `192.168.20.62:4243` (k2) instead of `192.168.20.105:4243` (old hub). Deploy this to all other NixOS machines so they can find the lighthouse at its new location.

```bash
cd /home/crussell/Code/cn
nix run .#deploy -- k1 k3 k4
```

After each deploy, verify that machine can still reach the nebula network:
```bash
ssh root@192.168.20.61 "ping -c 2 10.10.0.6"  # k1 → k2 (new hub)
ssh root@192.168.20.63 "ping -c 2 10.10.0.6"  # k3 → k2
ssh root@192.168.20.64 "ping -c 2 10.10.0.6"  # k4 → k2
```

### Step 7: Update Hetzner gateway

The Hetzner nginx config forwards to `10.10.0.6:443` which is a nebula IP. Since k2 now owns `10.10.0.6`, Hetzner should already be forwarding to the right place — **no changes needed on Hetzner**. But verify:

```bash
ssh root@178.156.171.212 "ping -c 2 10.10.0.6"
```

If ping works, the nginx stream proxy will work too.

### Step 8: Final verification

Run a comprehensive check of all public services:

```bash
echo "=== ntfy ===" && curl -s -o /dev/null -w "%{http_code}" https://ntfy.internal.crussell.io/v1/health
echo ""
echo "=== searxng ===" && curl -s -o /dev/null -w "%{http_code}" https://searxng.internal.crussell.io/
echo ""
echo "=== datenight ===" && curl -s -o /dev/null -w "%{http_code}" https://datenight.crussell.io/
echo ""
echo "=== jellyfin ===" && curl -s -o /dev/null -w "%{http_code}" https://jellyfin.crussell.io/
echo ""
echo "=== photos ===" && curl -s -o /dev/null -w "%{http_code}" https://photos.crussell.io/
echo ""
echo "=== homeassistant ===" && curl -s -o /dev/null -w "%{http_code}" https://homeassistant.crussell.io/
echo ""
```

## Troubleshooting

### Nebula fails to start on k2
- Check cert permissions: `ls -la /etc/nebula/ /etc/nebula-lh/`
- Check journal: `journalctl -u nebula-homelab -n 50`
- Common issue: cert files owned by wrong user. Fix: `chown root:nebula-homelab /etc/nebula/*`

### Caddy fails to start on k2
- Check if image exists: `podman images localhost/caddy-route53`
- Check if config exists: `ls /etc/caddy/Caddyfile /etc/caddy/aws.env`
- Check logs: `podman logs systemd-caddy --tail 50`
- If TLS certs are missing/not valid, Caddy will try to re-issue them. This can take up to 15 minutes (DNS propagation for the ACME DNS-01 challenge). Services will return 502 until certs are ready.

### Other machines can't reach 10.10.0.6
- They may still have the old `staticHostMap` pointing `10.10.0.1` at hub. Deploy the updated nebula-client config (Step 6).
- If k2's nebula is working but other machines can't reach it, try restarting nebula on those machines: `systemctl restart nebula-homelab`

### Hub's old nebula is interfering
- Make sure hub's nebula services are fully stopped: `ssh root@192.168.20.105 "systemctl status nebula nebula-lh-local"` — both should be inactive/dead.
- If they restarted (e.g., due to `Restart=always`), disable them: `ssh root@192.168.20.105 "sudo systemctl disable --now nebula nebula-lh-local"`

## After Migration

Once everything is verified:
- Hub (192.168.20.105) is fully decommissioned and ready for `nix run .#install -- hub`
- k2 is now the central proxy and nebula endpoint
- All services are distributed across k1-k4 as native NixOS services
- The only remaining container on k2 is Caddy (due to the Route53 plugin requirement)
