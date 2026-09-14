# ── Buzz server-side stack: buzz-acp harness + buzz CLI ────────────────
#
# Builds the two headless Rust binaries the server runs from upstream
# block/buzz, pinned to the CURRENT DESKTOP RELEASE TAG (desktop-v0.5.23
# as of 2026-09-14). The thinkpad desktop client auto-updates to the
# latest GitHub release; this pin is what keeps the server from silently
# diverging from it. When the desktop updates, bump rev + version here,
# redo the cargoHash dance (below), deploy bee, restart the buzz-acp
# units. Until then the server deliberately stays on the pinned tag.
#
# Pure-Rust TLS (rustls + ring — no openssl, no system TLS libs); the
# desktop Tauri app is EXCLUDED from the upstream workspace, so it never
# enters the build. Not built on purpose:
#   - buzz-relay    (cmake/opus; the relay runs as a container image)
#   - buzz-admin    (pulls buzz-media → rust-s3, a git dep chain; relay
#                    admin runs via `podman exec buzz-prod-relay-1
#                    buzz-admin`)
#   - buzz-dev-mcp / buzz-agent (old local-harness era; the agents are
#     dsh ACP agents now)
# aws-lc-sys is in the workspace lockfile via buzz-admin/buzz-dev-mcp/
# buzz-relay only — with this -p set it never compiles, so no cmake.
# Both built crates pin an explicit rustls ring provider because cargo
# feature unification across the packages would otherwise leave rustls
# without a selectable CryptoProvider (upstream documented gotcha).
#
# Toolchain: nixos-26.05 ships rustc 1.95.0 — exactly the upstream
# rust-toolchain.toml pin at this tag. If a future bump needs a newer
# rustc than stable nixpkgs ships, makeRustPlatform from unstable's
# rustc/cargo (or rust-overlay) is the escape hatch.
#
# Vendor strategy: cargoHash (fetchCargoVendor), NOT cargoLock. The
# workspace carries a [patch.crates-io] git fork (aws-creds via
# buzz-media → rust-s3) whose transitive crates re-resolve differently
# than the committed Cargo.lock records; importCargoLock's
# dedup-and-check never reaches a fixed point on those. fetchCargoVendor
# vendors straight from the source's own ./Cargo.lock as a single
# fixed-output (git deps via nix-prefetch-git). To bump: update rev +
# version, set cargoHash = "", build, paste the reported sha256.
{ pkgs, lib, }:
pkgs.rustPlatform.buildRustPackage {
  pname = "buzz-server";
  version = "0.5.23";

  src = pkgs.fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    # desktop release tag — same source the desktop AppImage ships
    rev = "desktop-v0.5.23";
    hash = "sha256-Mw8NXYLbLy9idH+doY287Mm3WuEXvAeO1B3H162rE70=";
  };

  cargoHash = "sha256-MFCN0LRVbqaRmCK5VgWgF58luvuJNTlpHwV+ULqXx2U=";

  # Build only what the server runs (see header for what this skips).
  cargoBuildFlags = [ "-p" "buzz-acp" "-p" "buzz-cli" ];

  nativeBuildInputs = [ ];
  buildInputs = [ ];

  # Workspace integration tests want a live relay + Postgres/Redis.
  doCheck = false;

  meta = {
    description = "Buzz server-side stack (buzz-acp agent harness + buzz CLI)";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-acp";
  };
}
