# Containerfile for the storyhub dev image — built once by the .build quadlet unit.
# Based on node:24-bookworm (Debian) so all worker system deps are available via apt.
#
# This is a pure infrastructure image: node + bun + pnpm + the worker's heavy
# system dependencies (vips, libreoffice, imagemagick, ghostscript, ffmpeg,
# pandoc, markitdown). No product code is baked in — the repo is bind-mounted
# into the running container (live HMR).
#
# The devcontainers/javascript-node:24 image lacks all these deps, and installing
# them on every cold start via apt-get would add ~2 minutes per boot. Building
# this image once (via the .build quadlet unit) caches them in podman's layer
# cache, so subsequent starts are fast.
FROM docker.io/library/node:24-bookworm

# pnpm (via corepack — the devcontainers image already has corepack; node:24
# has corepack too but we enable pnpm explicitly for version pinning)
RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

# bun (the worker runtime — storyhub-worker runs on bun, not node)
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v1.2.10"
ENV PATH="/root/.bun/bin:${PATH}"

# Worker system dependencies (mirrors storyhub-worker/Dockerfile + podman/
# Containerfile.storyhub-worker, adapted for Debian bookworm package names).
# These are needed for: image thumbnails (vips, sharp), document conversion
# (libreoffice, pandoc), video thumbnails (ffmpeg), and text extraction
# (markitdown, tesseract).
#
# Debian bookworm package name differences from alpine:
#   vips → libvips-tools (the CLI); libvips-dev for the headers
#   pango → libpango-1.0-0 + libpango1.0-dev
#   fonts-linux-libertine → fonts-linuxlibertine (no hyphen)
RUN apt-get update && apt-get install -y --no-install-recommends \
      postgresql-client \
      libvips-tools \
      libvips-dev \
      libreoffice \
      imagemagick \
      libpango-1.0-0 \
      libpango1.0-dev \
      libmagickwand-dev \
      ghostscript \
      ffmpeg \
      fontconfig \
      fonts-liberation \
      fonts-linuxlibertine \
      pandoc \
      texlive-xetex \
      python3 \
      python3-pip \
      git \
      curl \
    && rm -rf /var/lib/apt/lists/*

# markitdown (text extraction for document types)
RUN pip install --break-system-packages 'markitdown[all]'

WORKDIR /workspace

CMD ["bash"]
