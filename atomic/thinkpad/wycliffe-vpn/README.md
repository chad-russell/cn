# Wycliffe GlobalProtect VPN

Connect to the Wycliffe GlobalProtect VPN (portal
`wycliffe.gpcloudservice.com`) from a **rootful podman container** running
the official [GlobalProtect-openconnect](https://github.com/yuezk/GlobalProtect-openconnect)
image (`gpclient`).

## Why a container (and why not the built-in AnyConnect option)

Wycliffe's portal requires **CAS** (SAML/SSO) auth and rejects any client
below version 6.0 (`CAS is not supported by the client. Minimum client
version is 6.0`). Stock `openconnect` — what GNOME's built-in AnyConnect
option uses — identifies as v4.1 and doesn't implement CAS at all, so it
can't connect. `gpclient` implements the v6.0 protocol with CAS support and
is the known-working tool for Wycliffe.

`gpclient` isn't packaged for Fedora, but the upstream project publishes an
official Alpine image — so a container is the clean way to run it without
layering anything on the host.

## Why a script, not a systemd service

Unlike nebula (cert-based, auto-starts at boot), GlobalProtect needs a human
to authenticate through a browser **every time**. So this is an on-demand,
foreground, interactive process: run it when you need it, `Ctrl+C` to hang up.
Forcing it into a boot service would be the wrong shape.

## Usage

```bash
cd ~/Code/cn/atomic/thinkpad/wycliffe
./connect.sh
```

What happens:

1. `sudo` prompts for your password (the container is rootful — same reason
   as nebula: it needs to create `tun0` on the host and install routes).
2. `gpclient` starts and prints a URL (its `--browser remote` auth server,
   reachable from the host because of `--network host`).
3. Open that URL in Zen (or any browser) and complete the Wycliffe SSO login.
4. `gpclient` receives the cookie, `openconnect` brings up `tun0`, and the
   VPN routes apply to the host.
5. Leave the terminal open. **`Ctrl+C` to disconnect** — the container exits,
   the tunnel is torn down, routes removed.

Verify:

```bash
ip addr show tun0
ip route
```

## Notes / gotchas

- **Routing may affect nebula and the home LAN.** If Wycliffe's gateway
  configures a *full* tunnel (default route through `tun0`), it can hijack
  traffic to the nebula overlay (`10.10.0.0/24`) and the LAN
  (`192.168.20.0/24`) while connected. If that happens, we can add route
  exclusions so those subnets keep using the normal interface — observe
  first, then adjust.
- **SELinux:** uses the same `--network host` + `CAP_NET_ADMIN` + `/dev/net/tun`
  pattern as nebula, which works with SELinux enforcing. If you hit AVC
  denials, add `--security-opt label=disable` to the `podman run` in
  `connect.sh`.
- **sudo each connect:** every run prompts for your password. If that's
  annoying, a sudoers drop-in limited to this exact podman invocation can
  make it passwordless — but that's a deliberate convenience trade-off, not
  the default.
- **Stale tunnel cleanup** (rare — only if the terminal dies without a clean
  shutdown): `sudo ip link delete tun0`.

## Image tag / updating

The upstream Docker Hub repo only publishes a rolling **`snapshot`** tag
(versioned tags documented in the README are not actually published).
`snapshot` is rebuilt frequently from `main` and was current as of
2026-06-13. Because it's rolling, a fresh pull could in principle pick up an
upstream regression — but it's also the simplest way to track fixes.

Podman caches the image after the first pull (pull policy `missing`), so
re-running `./connect.sh` reuses the cached copy. To update to the latest
snapshot:

```bash
sudo podman pull docker.io/yuezk/globalprotect-openconnect:snapshot
```

To pin a known-good build for immutability, append a digest:

```bash
IMAGE="docker.io/yuezk/globalprotect-openconnect:snapshot@sha256:<digest>"
```

Get the current digest after a successful pull with:

```bash
sudo podman inspect --format '{{.Digest}}' \
  docker.io/yuezk/globalprotect-openconnect:snapshot
```

Release notes: https://github.com/yuezk/GlobalProtect-openconnect/releases
