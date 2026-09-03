# THI-AHA Flutter dev image — full Android toolchain + emulator, Flutter pinned to .fvmrc.
#
# Built by the thi-aha-dev.build quadlet unit on think → localhost/thi-aha-dev:latest.
#
# Design notes:
#  - Everything heavy is baked in at BUILD time (Android SDK, emulator, API-36
#    google_apis system image, NDK 28.2.13676358, Flutter 3.41.9 == .fvmrc pin),
#    so container starts never download anything.
#  - The flutter repo is NOT in the image — the quadlet bind-mounts
#    ~/Gloo/thi-aha-flutter at /workspace. No repo changes needed to run.
#  - Root inside the container == crussell on the host (rootless podman).
#  - The bootstrap script is inlined via heredoc (not COPY) because the
#    .build unit's SetWorkingDirectory resolves to the quadlet symlink dir,
#    where this file's siblings don't exist. Keeps the image self-contained.
#  - SELinux is disabled on think, so no :Z/:z mount labels anywhere.

FROM ubuntu:24.04

ARG FLUTTER_VERSION=3.41.9
ARG CMDLINE_TOOLS=13114758
ARG ANDROID_PLATFORM=android-36
ARG BUILD_TOOLS=36.0.0
ARG SYSIMG=system-images;android-36;google_apis;x86_64
ARG NDK=28.2.13676358

ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_HOME=/opt/android-sdk \
    FLUTTER_ROOT=/opt/flutter \
    PUB_CACHE=/home/dev/.pub-cache \
    GRADLE_USER_HOME=/home/dev/.gradle \
    ANDROID_AVD_HOME=/home/dev/.android/avd \
    THI_SYSIMG=${SYSIMG} \
    THI_AVD_NAME=thi_pixel7_api36

# x11-utils/xauth: DISPLAY probing + xauth for the emulator window.
# mesa-vulkan-drivers + libgl1-mesa-dri: host-GPU rendering via /dev/dri.
RUN apt-get update && apt-get install -y --no-install-recommends \
      openjdk-21-jdk-headless \
      git curl unzip xz-utils ca-certificates \
      tmux x11-utils xauth \
      mesa-vulkan-drivers libgl1-mesa-dri vulkan-tools \
      procps \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator:${FLUTTER_ROOT}/bin:${PATH}

# --- Android SDK ---
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip -o /tmp/clt.zip \
    && unzip -q /tmp/clt.zip -d /tmp/clt \
    && mv /tmp/clt/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm -rf /tmp/clt /tmp/clt.zip

RUN yes | sdkmanager --licenses >/dev/null 2>&1 || true

RUN sdkmanager \
      "platform-tools" \
      "emulator" \
      "platforms;${ANDROID_PLATFORM}" \
      "build-tools;${BUILD_TOOLS}" \
      "${SYSIMG}" \
      "ndk;${NDK}"

# --- Flutter, exact .fvmrc pin (tarball = pre-stamped, avoids the clone version-stamp warning) ---
RUN git config --global --add safe.directory ${FLUTTER_ROOT} \
    && curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
       | tar -xJ -C /opt \
    && flutter config --no-analytics \
    && flutter --version \
    && flutter doctor || true

# --- late system-dep layer: runtime libs the emulator needs that the base
# --- apt set missed. libpulse0: qemu-system links it even with -audio none
# --- (ubuntu:24.04 ships without it — emulator dies with a loader error).
# --- Separate late layer so lib additions never re-download the SDK layers.
RUN apt-get update -qq && apt-get install -y --no-install-recommends libpulse0 \
    && rm -rf /var/lib/apt/lists/*

# --- entrypoint: creates the AVD on first run, boots the emulator inside tmux,
# --- waits for boot, then sleeps forever (container == emulator lifecycle;
# --- stdout lands in the systemd journal via conmon) ---
RUN mkdir -p /opt/dev && cat > /opt/dev/thi-aha-dev-entrypoint.sh <<'EOF'
#!/usr/bin/env bash
# Idempotent: creates the AVD on first run, starts the emulator inside tmux,
# waits for boot. Safe to re-run on every container start.
set -uo pipefail
say(){ echo "[thi-aha-bootstrap] $*"; }

# 1. Pick a working X display (:0 = niri's Xwayland on think, via
#    xwayland-satellite; :1 is the stray systemd-user satellite).
#    NOTE: probe with xdpyinfo — xset is NOT in the ubuntu:x11-utils set as
#    pulled here (silently absent), xdpyinfo is verified present.
xdpyinfo -display "${DISPLAY:-:0}" >/dev/null 2>&1 && export DISPLAY="${DISPLAY:-:0}"
if ! xdpyinfo -display "${DISPLAY:-}" >/dev/null 2>&1; then
  for d in :0 :1 :2; do
    if xdpyinfo -display "$d" >/dev/null 2>&1; then export DISPLAY="$d"; break; fi
  done
fi
if xdpyinfo -display "${DISPLAY:-}" >/dev/null 2>&1; then
  say "emulator window on DISPLAY=$DISPLAY"
  WINDOWED=1
else
  say "no working X display — falling back to headless emulator (-no-window)"
  WINDOWED=0
fi

# 2. Create the AVD on first run.
if [ ! -f "${ANDROID_AVD_HOME}/${THI_AVD_NAME}.avd/config.ini" ]; then
  say "creating AVD ${THI_AVD_NAME} from ${THI_SYSIMG}"
  echo no | avdmanager create avd -n "${THI_AVD_NAME}" -k "${THI_SYSIMG}" -d pixel_7 >/dev/null
fi

# 3. Start the emulator in tmux (detached from this script and from shells).
EMU_ARGS="-avd ${THI_AVD_NAME} -no-snapshot -no-boot-anim -audio none -memory 3072 -no-metrics"
tmux kill-session -t emulator 2>/dev/null || true
if [ "$WINDOWED" = 1 ]; then
  tmux new-session -d -s emulator "emulator ${EMU_ARGS} -gpu host; echo EMULATOR_EXITED; sleep infinity"
else
  tmux new-session -d -s emulator "emulator ${EMU_ARGS} -no-window -gpu swiftshader_indirect; echo EMULATOR_EXITED; sleep infinity"
fi

# 4. If a windowed emulator died instantly (host GPU mode refused), retry swiftshader.
sleep 12
if [ "$WINDOWED" = 1 ] && ! adb devices 2>/dev/null | grep -qE 'emulator-[0-9]+[[:space:]]+device'; then
  if tmux capture-pane -t emulator -p 2>/dev/null | grep -q EMULATOR_EXITED; then
    say "emulator exited with -gpu host — retrying with -gpu swiftshader_indirect"
    tmux kill-session -t emulator 2>/dev/null || true
    tmux new-session -d -s emulator "emulator ${EMU_ARGS} -gpu swiftshader_indirect; echo EMULATOR_EXITED; sleep infinity"
  fi
fi

# 5. Wait for full boot (first cold boot of a fresh AVD takes a few minutes).
say "waiting for emulator boot ..."
adb wait-for-device
BOOTED=""
for i in $(seq 1 150); do
  b=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$b" = "1" ]; then BOOTED=1; break; fi
  sleep 4
done

if [ -n "$BOOTED" ]; then
  say "BOOT COMPLETE — display=${DISPLAY:-headless}, avd=${THI_AVD_NAME}"
  say "gpu check: $(tmux capture-pane -t emulator -p | grep -m1 -oE 'gpu:[^ ]+' || echo unknown)"
  adb shell input keyevent 82 >/dev/null 2>&1 || true   # wake/unlock
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
else
  say "WARNING: boot did not complete — inspect with:"
  say "  podman exec thi-aha-dev tmux capture-pane -t emulator -p"
  say "  podman exec thi-aha-dev adb devices"
fi

exec sleep infinity
EOF
RUN chmod +x /opt/dev/thi-aha-dev-entrypoint.sh

ENTRYPOINT ["/opt/dev/thi-aha-dev-entrypoint.sh"]
