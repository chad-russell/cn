# Hetzner VPS - Public Gateway

**Hostname:** reverse-proxy
**IP:** 178.156.171.212
**Nebula:** 10.10.0.2 (lighthouse #2)

## Role

Public gateway for `*.crussell.io` traffic. Forwards all HTTPS to crussell-srv via Nebula mesh VPN.

## Architecture

```
Internet (*.crussell.io)
    │
    ▼
Hetzner nginx (SSL passthrough :443)
    │
    ▼ stream proxy to 10.10.0.1:443
    │
crussell-srv (Nebula 10.10.0.1)
    │
    ▼
Caddy → backend services
```

## nginx Configuration

`/etc/nginx/nginx.conf` - Simple stream proxy (SSL passthrough):

```nginx
stream {
    upstream homelab_https {
        server 10.10.0.1:443;  # crussell-srv via Nebula
    }

    upstream homelab_http {
        server 10.10.0.1:80;
    }

    server {
        listen 443;
        proxy_pass homelab_https;
    }

    server {
        listen 80;
        proxy_pass homelab_http;
    }
}
```

**Key Point:** nginx doesn't terminate SSL - it passes through to Caddy on crussell-srv which handles certificates via Route53 DNS challenge.

## Management

```bash
# SSH (requires ssh-agent)
ssh root@178.156.171.212

# Reload nginx
nginx -t && systemctl reload nginx

# Check status
systemctl status nginx

# View logs
journalctl -u nginx -f
```

## Firewall

```bash
# Required ports
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 4242/udp  # Nebula
```

## Nebula

Hetzner runs as Nebula lighthouse #2, providing connectivity for roaming devices (phone, laptop).

- **Config:** `/etc/nebula/config.yaml`
- **Service:** `systemctl status nebula`
- **IP:** 10.10.0.2

## Notes

- SSH requires ssh-agent with passphrase-protected key
- Access via Hetzner Cloud Console if locked out
- Traffic switched from Tailscale (100.121.155.14) to Nebula (10.10.0.1) on 2026-02-28
