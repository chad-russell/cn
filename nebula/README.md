# Nebula Network Reference

This document is the source of truth for the current Nebula setup in this repo.

It is written for both humans and coding agents and focuses on current state, operations, and expansion.

## Goals

- Keep homelab access working from outside home networks.
- Keep local access working at home even if ISP/public internet is down.
- Avoid pinning service traffic to LAN-only addresses for roaming clients.

## Current Topology

Overlay CIDR: `10.10.0.0/24`

- `10.10.0.1` - local lighthouse identity on `hub` (container, UDP `4243`, discovery-only)
- `10.10.0.2` - Hetzner lighthouse + relay (public, UDP `4242`)
- `10.10.0.3` - TrueNAS host
- `10.10.0.5` - AI server host
- `10.10.0.6` - `hub` host/services endpoint (Caddy/backends)
- `10.10.0.10` - thinkpad
- `10.10.0.11` - phone

Important split identity on `hub`:

- Local lighthouse: `10.10.0.1`
- Service host identity: `10.10.0.6`

This split is what allows both reliable roaming and local-only resiliency.

## Traffic Flow

At home (Wi-Fi):

- Client discovers peers via local lighthouse (`10.10.0.1`)
- Client prefers LAN underlay (`192.168.20.0/24`) and talks directly to `10.10.0.6`

Away from home:

- Client reaches Hetzner lighthouse (`10.10.0.2`)
- Direct path is attempted first; relay via Hetzner is used when needed

Public ingress (`*.crussell.io`):

- Internet -> Hetzner nginx stream proxy -> `10.10.0.6:443` -> Caddy -> backend service

Internal DNS (`*.internal.crussell.io`):

- Route53 points to `10.10.0.6`

## Important Files

Repo:

- `nebula/configs/hub-host.yaml` - main `hub` host config (`10.10.0.6`)
- `nebula/configs/hub-lighthouse.yaml` - local lighthouse config (`10.10.0.1`)
- `nebula/configs/gateway.yaml` - Hetzner public lighthouse/relay config
- `nebula/configs/phone.yaml` - phone config (embedded cert/key)
- `nebula/configs/thinkpad.yaml` - laptop template
- `nebula/configs/nas.yaml` - TrueNAS config
- `nebula/configs/ai.yaml` - AI server config
- `nebula/quadlets/nebula-lh-local.container` - local lighthouse quadlet
- `nebula/pki/` - CA and host cert/key material
- `nebula/scripts/nebula` and `nebula/scripts/nebula-cert` - local binaries

Live on `hub`:

- `/etc/nebula/config.yaml` - active host config for `10.10.0.6`
- `/etc/nebula/*.crt|*.key` - active host certs/keys
- `/etc/nebula-lh/config.yaml` - local lighthouse config
- `/etc/nebula-lh/*.crt|*.key` - local lighthouse certs/keys
- `/etc/containers/systemd/nebula-lh-local.container` - quadlet source

Live on Hetzner:

- `/etc/nebula/hetzner-lh.yaml`
- `/etc/nebula/hetzner-lh.crt`
- `/etc/nebula/hetzner-lh.key`
- `systemd` service: `nebula`

## Active Services

On `hub`:

- `nebula.service` (binary/systemd) -> host identity `10.10.0.6` on UDP `4242`
- `nebula-lh-local.service` (quadlet-generated) -> local lighthouse identity `10.10.0.1` on UDP `4243`

On Hetzner:

- `nebula.service` -> lighthouse + relay identity `10.10.0.2` on UDP `4242`

## Certificate Model

CA files:

- `nebula/pki/ca.crt`
- `nebula/pki/ca.key` (do not commit externally)

Required cert identities:

- `crussell-lh-local` -> `10.10.0.1/24`, groups: `lighthouse`
- `hub-host` -> `10.10.0.6/24`, groups: `servers,lighthouse`, unsafe networks: `192.168.20.0/24`
- `hetzner-lighthouse` -> `10.10.0.2/24`, groups: at least `lighthouse,client`

Generate cert examples:

```bash
cd /var/home/crussell/Code/cn/nebula/pki

# local lighthouse
../scripts/nebula-cert sign \
  -ca-crt ca.crt \
  -ca-key ca.key \
  -name "crussell-lh-local" \
  -networks "10.10.0.1/24" \
  -groups "lighthouse" \
  -out-crt crussell-lh-local.crt \
  -out-key crussell-lh-local.key

# hub host/services
../scripts/nebula-cert sign \
  -ca-crt ca.crt \
  -ca-key ca.key \
  -name "hub-host" \
  -networks "10.10.0.6/24" \
  -groups "servers,lighthouse" \
  -unsafe-networks "192.168.20.0/24" \
  -out-crt hub-host.crt \
  -out-key hub-host.key
```

## Deploy / Update Workflow

### Update `hub` host (`10.10.0.6`)

```bash
sudo cp /var/home/crussell/Code/cn/nebula/configs/hub-host.yaml /etc/nebula/config.yaml
sudo cp /var/home/crussell/Code/cn/nebula/pki/ca.crt /etc/nebula/ca.crt
sudo cp /var/home/crussell/Code/cn/nebula/pki/hub-host.crt /etc/nebula/hub-host.crt
sudo cp /var/home/crussell/Code/cn/nebula/pki/hub-host.key /etc/nebula/hub-host.key
sudo systemctl restart nebula
```

### Update local lighthouse (`10.10.0.1`)

```bash
sudo mkdir -p /etc/nebula-lh
sudo cp /var/home/crussell/Code/cn/nebula/configs/hub-lighthouse.yaml /etc/nebula-lh/config.yaml
sudo cp /var/home/crussell/Code/cn/nebula/pki/ca.crt /etc/nebula-lh/ca.crt
sudo cp /var/home/crussell/Code/cn/nebula/pki/crussell-lh-local.crt /etc/nebula-lh/crussell-lh-local.crt
sudo cp /var/home/crussell/Code/cn/nebula/pki/crussell-lh-local.key /etc/nebula-lh/crussell-lh-local.key

sudo cp /var/home/crussell/Code/cn/nebula/quadlets/nebula-lh-local.container /etc/containers/systemd/nebula-lh-local.container
sudo systemctl daemon-reload
sudo systemctl restart nebula-lh-local.service
```

Firewall requirement on `hub`:

```bash
sudo firewall-cmd --permanent --add-port=4242/udp
sudo firewall-cmd --permanent --add-port=4243/udp
sudo firewall-cmd --reload
```

### Update Hetzner lighthouse/relay

```bash
scp -i ~/.ssh/id_rsa nebula/configs/hetzner-lh.yaml root@178.156.171.212:/etc/nebula/hetzner-lh.yaml
scp -i ~/.ssh/id_rsa nebula/pki/hetzner-lh.crt root@178.156.171.212:/etc/nebula/hetzner-lh.crt
scp -i ~/.ssh/id_rsa nebula/pki/hetzner-lh.key root@178.156.171.212:/etc/nebula/hetzner-lh.key
ssh -i ~/.ssh/id_rsa root@178.156.171.212 "systemctl restart nebula"
```

## Client Expectations

All roaming clients should:

- statically map only lighthouses
- list both lighthouses in `lighthouse.hosts`
- enable relays and include `10.10.0.2` in `relay.relays`
- include `preferred_ranges: ["192.168.20.0/24"]`

Phone template currently follows this pattern in `nebula/configs/phone.yaml`.

## Adding A New Machine

1. Pick a free Nebula IP in `10.10.0.0/24`.
2. Sign cert/key with appropriate groups.
3. Create machine config from a similar host template.
4. Add lighthouse mappings:
   - `10.10.0.1 -> 192.168.20.105:4243`
   - `10.10.0.2 -> 178.156.171.212:4242`
5. Set `lighthouse.hosts` to both `10.10.0.1` and `10.10.0.2`.
6. For roaming nodes, enable relay via `10.10.0.2`.
7. Deploy config/certs, start Nebula, verify with ping and service checks.

## Testing Checklist

On `hub`:

```bash
ping -c 3 10.10.0.2
sudo systemctl status nebula --no-pager -n 15
sudo systemctl status nebula-lh-local.service --no-pager -n 15
```

At home (Wi-Fi):

- Client can reach `10.10.0.6`
- `karakeep.internal.crussell.io` works

Away from home (cellular/public Wi-Fi):

- Client can reach `10.10.0.2`
- Client can reach `10.10.0.6`
- `karakeep.internal.crussell.io` works

## Troubleshooting

On `hub`:

```bash
sudo journalctl -u nebula --no-pager -n 100
sudo journalctl -u nebula-lh-local.service --no-pager -n 100
sudo ss -ulnp | rg "4242|4243"
ip addr show nebula0
```

On Hetzner:

```bash
journalctl -u nebula --no-pager -n 100
systemctl status nebula
```

Useful indicators:

- If roaming can hit `10.10.0.2` but not `10.10.0.6`, verify relay groups on Hetzner cert.
- If local discovery fails, verify UDP `4243` open and local lighthouse service running.
- If LAN route to `192.168.20.0/24` fails, verify `unsafe-networks` exists in the cert for the `via` host (`10.10.0.6`).

## Security Notes

- Never commit `ca.key` outside trusted private storage.
- Treat embedded mobile keys in `nebula/configs/phone.yaml` as sensitive.
- Do not force-push or rewrite cert history unless intentionally rotating/revoking.
