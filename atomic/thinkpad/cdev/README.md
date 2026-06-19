# cdev — isolated dev/AI sandbox

A Fedora-toolbox-based dev image (`Containerfile`) plus a hardened runner
(`run.sh`) whose entire purpose is: **let an AI agent (or you) install
packages, edit files, and run anything inside, with the guarantee that
nothing outside the explicit mounts can be reached or modified.**

The image is just a base. **All of the safety comes from `run.sh`** — i.e.
from how the container is invoked, not from what's installed in it.

> Separate concern: [`impermanence/`](./impermanence) holds a script +
> allow-list that wipes the **host** `$HOME` (Silverblue) on demand,
> keeping only listed dirs (`.ssh`, `~/Code`, `~/.config`, …). See its
> README. It runs on the host, not in the sandbox.

## The isolation model

Rootless Podman on a SELinux-Enforcing host gives you five independent layers
of isolation, each of which has to fail for the host to be affected:

| Layer | What it guarantees |
|---|---|
| **User namespace** | "root" *inside* the container maps to your **unprivileged** host UID (1000), never host root. Privilege inside ≠ privilege outside. This is the load-bearing wall. |
| **Mount namespace** | The container only sees what you **explicitly mount**. Host `$HOME`, `~/.ssh`, `~/.gnupg`, `/etc`, `/var`, the Podman socket — none of it is present. |
| **SELinux (`container_t`)** | Even files the mount namespace *can* see are denied unless labeled `container_file_t`. This is on by default with SELinux Enforcing; `:Z` on a bind mount relabels it so the container may access it. |
| **Dropped capabilities** | `--cap-drop=ALL` removes `CAP_SYS_ADMIN`, `CAP_NET_ADMIN`, etc., so even container-root can't perform privileged kernel operations. |
| **no-new-privileges** | Blocks setuid binaries inside from gaining privilege. |

Because of the user namespace, **container-root is just you.** If an agent
`dnf install`s something, it writes to the container's own writable layer
(lives under `~/.local/share/containers/storage`, not your real paths). If it
`rm -rf /` inside, it destroys the container's overlay, not your host. The
host's real root filesystem is not even mounted.

### The residual host surface (be honest about this)

Isolation is not magic; it's "everything except what you explicitly poke a
hole for." `run.sh` pokes exactly two holes:

1. **`$CDEV_PROJECT` → `/work`** (read-write). This *is* a real write path to
   a host directory — by design, so the agent can edit your code. If you point
   it at `~/Code/foo`, the agent can read and modify `~/Code/foo` and nothing
   else under `~/Code`. Point it at nothing (`CDEV_PROJECT=""`) for a sealed
   sandbox.
2. **The `cdev-home` named volume → container `$HOME`** (read-write). This is
   *Podman-owned storage*, not your real `$HOME`. Agent dotfiles, caches,
   user-level installs (npm/cargo/pip `--user`) land here. It persists across
   runs; `podman volume rm cdev-home` wipes it.

Everything else — your real `$HOME`, SSH keys, GPG keyring, browser data,
host `/etc`, other projects — is unreachable.

## Modes

`CDEV_MODE=` selects how privileged the agent is *inside*:

| Mode | Runs as | Can `dnf install`? | Network | Rootfs | Use when |
|---|---|---|---|---|---|
| `root` (default) | container root (= host you) | yes | yes | writable | Autonomous agent that should install whatever it wants |
| `user` | your UID (`keep-id`) | no (no sudo) | yes | writable | Least-privilege; image already has everything |
| `airtight` | container root | no | **none** | **read-only** | "Analyze this code, touch nothing." Writes only to home volume + `/tmp` |

`root` mode is the one that matches "feel free to do anything." It is safe
because container-root maps to unprivileged-you (see user namespace, above).

## Daily use

```bash
./build.sh                                   # build once (rebuild after Containerfile edits)

./run.sh                                     # interactive zsh, sandbox in $PWD
CDEV_PROJECT=~/Code/some-repo ./run.sh       # expose one repo at /work
CDEV_PROJECT=~/Code/some-repo ./run.sh pi    # run pi in the sandbox against that repo

CDEV_MODE=airtight CDEV_PROJECT=~/Code/x ./run.sh   # read-only analysis, no net

# Copy work out of the isolated home volume (home is NOT on the host):
podman run --rm -v cdev-home:/h localhost/cdev ls /h
podman run --rm -v cdev-home:/h -v "$PWD/out:/out:Z" localhost/cdev cp -a /h/foo /out/

# Reset to a pristine sandbox:
podman rm -f cdev 2>/dev/null; podman volume rm cdev-home
```

### What does *not* persist

With the default ephemeral run (`--rm`), the container's rootfs is discarded
on exit. **System packages installed via `dnf` do not survive the next run.**
Two ways to keep them:

- **Bake them** into `Containerfile` and `./build.sh` (the intended model —
  matches the repo philosophy: "anything you miss becomes a Containerfile
  line next time").
- **`CDEV_EPHEMERAL=0`** to keep the container between runs; then `podman rm`
  to reset.

User-level state (shell history, `~/.cargo`, npm globals in `~`, editor
config, agent credentials) *does* persist, via the `cdev-home` volume.

## Credentials for the agent

The agent (e.g. `pi`) will need its own API keys / git identity. Because the
home volume is isolated, these live **inside the sandbox**, never on your host
`$HOME`:

- `git` identity is already baked at `/etc/gitconfig` (system-wide, applies to
  every user in the container).
- For git push, do **not** mount `~/.ssh` (that would expose your host keys).
  Instead put an agent-specific deploy key inside the volume, or forward the
  host agent read-only: add `--ssh agent` to `run_args` (lets the container
  *use* keys via the socket without the key files being present).
- API keys: set them up once inside the sandbox, or pass via `-e`/`--env-file`
  at run time.

## Verify the isolation yourself

Run these **on the host** (not inside the sandbox) to see the boundaries:

```bash
# Container process is confined by SELinux to container_t:
ps -eZ | grep -E 'container_t'

# The user-namespace mapping: container UID 0 -> your host UID (1000):
podman exec cdev cat /proc/self/uid_map     # fields: container-id host-id range

# Capabilities actually granted (should be near-empty with --cap-drop=ALL):
podman exec cdev capsh --print 2>/dev/null || podman exec cdev grep Cap /proc/self/status

# From inside the sandbox — your real home is simply not there:
podman exec cdev ls /var/home/crussell      # only what the volume provides
```

## Never do these

Each of these defeats the sandbox:

- **`--privileged`** — turns off all of the above.
- **Mounting the Podman/Docker socket** (`-v /run/podman/...` or
  `$XDG_RUNTIME_DIR/podman/podman.sock`) — the agent can spawn privileged
  containers and escape. Rootless-in-rootless via the socket is a full break.
- **Mounting `~/.ssh`, `~/.gnupg`, or all of `$HOME`** — hands the agent your
  real secrets. Use the isolated volume and an agent-specific identity.
- **`--cap-add=SYS_ADMIN`** and friends casually — re-add only the specific
  capability a tool complains about (e.g. `SYS_PTRACE` for `strace`/`gdb`
  attach, `NET_RAW` for `ping`), and only in non-airtight modes.

## What "barring runtime bugs" means here

The remaining theoretical risks are: a kernel or Podman/runc/crun
vulnerability, or a misconfiguration (the "never do" list above). Keep the
host and Podman updated; don't punch the holes above; and a `podman volume rm`
is always a full reset.
