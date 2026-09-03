# THI-AHA Flutter dev stack (Gloo — americanbible/thi-aha-flutter)

Containerized Android emulator + pinned Flutter toolchain for running the
THI-AHA app on think, with **zero host installs** (no flutter/java/sdk on the
host — everything lives in `localhost/thi-aha-dev:latest`, built from the
`Containerfile` in this directory).

- **Repo:** `~/Gloo/thi-aha-flutter` (bind-mounted at `/workspace`, never
  modified by the stack)
- **Flutter pin:** 3.41.9 == `.fvmrc` exact
- **AVD:** `thi_pixel7_api36` (google_apis x86_64, API 36) — created on first
  start, userdata persists in the `thi-aha-dev-android` volume
- **Emulator window:** Xwayland display (`/tmp/.X11-unix` mounted; bootstrap
  probes `:0`/`:1`/`:2` and falls back to `-no-window` if none works)
- **Driving the stack (from bee over SSH):**

```
systemctl --user start thi-aha-dev            # build + container + emulator boot
systemctl --user stop  thi-aha-dev            # tear it all down

podman exec thi-aha-dev adb devices           # emulator-5554 device
podman exec thi-aha-dev tmux attach -t flutter   # interactive flutter run
podman exec thi-aha-dev tmux send-keys -t flutter r Enter   # hot reload
podman exec thi-aha-dev adb exec-out screencap -p > /tmp/s.png
podman exec thi-aha-dev adb logcat -d
```

- **Run the app:**

```
podman exec -it thi-aha-dev bash
  cd /workspace && flutter run --flavor dev --target lib/main_dev.dart -d emulator-5554
```

(Use `tmux new-session -d -s flutter "..."` so the session survives detached
SSH; attach locally with `podman exec -it thi-aha-dev tmux attach -t flutter`.)

- **Upgrade Flutter pin:** edit `FLUTTER_VERSION` in the Containerfile,
  `systemctl --user restart thi-aha-dev-build.service`, then restart the stack.
- **First start:** image build (~5–10 min) + AVD cold boot (~2–4 min). After
  caches warm, starts take ~30–60s.
- **Hermes note:** this stack is described in the podman-quadlet-dev-stacks
  skill (bee) — update `references/stacks.md` when changing ports/behavior.
