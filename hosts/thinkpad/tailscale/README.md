# Tailscale (on-demand)

A rootful Podman Quadlet for [Tailscale](https://tailscale.com) on the
ThinkPad, mirroring the `../nebula/` pattern. Deliberately **on-demand**: the
unit is installed but **not enabled at boot** and **not started** by setup, so
it sits inert (zero CPU/memory/network cost) until you bring it up.

## Why a container

Same reasoning as `../nebula/`: Tailscale needs to create a host TUN device
(`tailscale0`) and install host routes, which means a host network namespace +
real `CAP_NET_ADMIN`, i.e. rootful podman. Containerizing keeps the atomic host
image lean (no `rpm-ostree install` / image rebuild + reboot) and tracks the
pattern already established for VPNs on this machine.

## Why not auto-start at boot

Tailscale usage on this host is occasional. Nebula is the always-on homelab
overlay (auto-starts, auto-restarts); Tailscale is for ad-hoc external access
and is started/stopped manually. Because the unit has no `[Install]` section
and `install.sh` does not run `systemctl enable`, it contributes zero cost at
boot — nothing runs until `sudo systemctl start tailscale`.

## Auth model: browser, cached

On first `tailscale up`, Tailscale prints a URL; complete the login in your
browser. The device identity + auth state are written to the rootful
`tailscale-state` podman volume (`/var/lib/tailscale` in the container), so
subsequent `systemctl start tailscale` cycles reconnect automatically from
cache — no re-browser-auth each time.

This is why the state volume is load-bearing: without it, every start would
require a fresh browser login.

## Usage

### One-time install

```bash
cjust tailscale
```

### First-time auth (after install)

containerboot runs `tailscale up` itself on boot (using the `TS_*` env vars
declared in the Quadlet), so you do **not** run `tailscale up` manually — just
start the service and watch the journal for the auth URL it prints:

```bash
sudo systemctl start tailscale
sudo journalctl -u tailscale -f                 # watch for the auth URL
# open the URL in a browser, complete the login
sudo podman exec tailscale tailscale status     # confirm connected
```

### Day to day

```bash
sudo systemctl start tailscale              # VPN on (auto-reconnects from cache)
sudo systemctl stop tailscale               # VPN off (tunnel + routes torn down)
sudo journalctl -u tailscale -f
```

**Changing Tailscale prefs (hostname, routes, exit-node, etc.):** edit the
`TS_*` env vars in `tailscale.container` and re-run `cjust tailscale`. Do **not**
run `tailscale up --<flag>` manually via `podman exec` to change a pref.
containerboot runs `tailscale up` on every boot, and Tailscale refuses that
command once the state holds any non-default pref that the boot-time `up`
doesn't re-mention ("changing settings via 'tailscale up' requires mentioning
all non-default flags"). A manual `tailscale up --accept-routes` (etc.) writes
the pref to state but leaves containerboot's boot-time `up` unaware of it, so
the next `systemctl start` crash-loops with exit 1. The Quadlet declares every
non-default pref as an env var so they always match.

The `tailscale` CLI lives inside the container, so all client commands go
through `sudo podman exec tailscale tailscale …`. This keeps the host image
untouched (no layered `tailscale` client package). **Read-only commands are
safe** (status, netcheck, ip, ping). **Pref-changing commands are not** — see
the warning above (use the `TS_*` env vars instead of `tailscale up/set`).

Safe, read-only client commands:

```bash
sudo podman exec tailscale tailscale status
sudo podman exec tailscale tailscale netcheck
sudo podman exec tailscale tailscale ip     # the host's tailnet IP
```

### Verify the tunnel

```bash
ip addr show tailscale0
ip route
```

## Updating the image

```bash
sudo podman pull docker.io/tailscale/tailscale:latest
sudo systemctl restart tailscale            # only if currently running
```

To pin a known-good build for immutability, append a digest:

```bash
IMAGE="docker.io/tailscale/tailscale:latest@sha256:<digest>"
```

Get the current digest after a successful pull with:

```bash
sudo podman inspect --format '{{.Digest}}' docker.io/tailscale/tailscale:latest
```

Release notes: https://github.com/tailscale/tailscale/releases

## Files

- `tailscale.container` — the rootful Quadlet unit (no `[Install]` by design).
- `install.sh` — install the unit + `daemon-reload`. Does NOT enable/start.
- `setup.sh` — pull image + run `install.sh` (the `cjust tailscale` entry point).

## Notes / gotchas

- **Routing may affect nebula and the home LAN.** If you use Tailscale with a
  default-route exit node (`--exit-node=…`) or accept remote routes
  (`--accept-routes`), it can hijack traffic to the nebula overlay
  (`10.10.0.0/24`) and the LAN (`192.168.20.0/24`) while connected. Observe
  first (`ip route`); toggle these flags selectively rather than blindly.
- **SELinux:** uses the same `--network host` + `CAP_NET_ADMIN` + `/dev/net/tun`
  pattern as nebula, which works with SELinux enforcing. If you hit AVC
  denials, add `--security-opt label=disable` to the `PodmanArgs=` line in
  `tailscale.container` and re-run `cjust tailscale`.
- **State volume is rootful.** It lives in root podman storage; inspect with
  `sudo podman volume inspect tailscale-state`. Don't delete it casually —
  losing it means re-authenticating the device and orphaning the old node
  entry in the Tailscale admin console.
- **containerboot env vars are load-bearing** (not optional). The upstream
  image boots via `containerboot`, which reads `TS_*` env vars. Two defaults
  are wrong for our use, which is why the Quadlet sets them explicitly:
  - `TS_USERSPACE=false` — containerboot defaults to `true`, which runs
    `tailscaled --tun=userspace-networking`: a SOCKS5/HTTP proxy mode that
    authenticates fine but **never creates the `tailscale0` TUN** and doesn't
    route host traffic. Symptom: `tailscale up` succeeds, `ip a` shows no
    `tailscale0`. Forcing false makes `tailscaled` create a real kernel TUN
    (works because the unit grants `Network=host` + `NET_ADMIN` +
    `/dev/net/tun`).
  - `TS_STATE_DIR=/var/lib/tailscale` — containerboot defaults to empty,
    which makes it run `tailscaled --state=mem:`: state lives **only in RAM**
    and is lost on every container restart. Forgetting this env var looks like
    it works after first auth, but every `systemctl restart tailscale`
    silently wipes the auth and forces a fresh browser login. Pointing it at
    the volume mount makes device identity + auth persist.

  If a future image revision changes either default, verify against
  `cmd/containerboot/{settings.go,tailscaled.go}` in the tailscale repo.
