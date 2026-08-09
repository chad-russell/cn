# ── Buzz CLI stack: buzz-acp + buzz-cli + buzz-agent + buzz-dev-mcp ────
#
# Builds four headless Rust binaries from upstream block/buzz. These are
# pure-Rust (rustls/ring TLS — no openssl), and do NOT build buzz-relay, so the
# cmake/opus toolchain the relay needs is avoided entirely. buzz-admin is
# intentionally excluded: it pulls buzz-media → rust-s3 (a git dep); mint agent
# keypairs with `nak` instead.
#
# Toolchain is pinned to the exact version from upstream rust-toolchain.toml
# (1.95.0), which is newer than nixos-25.11 ships — hence the passed-in
# rustToolchain (built from rust-overlay in flake.nix).
#
# Vendor strategy: cargoHash (fetchCargoVendor), NOT cargoLock. The workspace
# has git deps (aws-creds via buzz-media → rust-s3; mesh-llm-api-client via
# buzz-relay-mesh) whose transitive crates re-resolve differently than the
# committed Cargo.lock records. cargoLock's importCargoLock runs a
# dedup-and-check that regenerates and compares the lockfile, which never
# reaches a fixed point on those git deps. fetchCargoVendor vendors straight
# from the source's own ./Cargo.lock as a single fixed-output (fetching git deps
# via nix-prefetch-git), so there's no consistency check and no per-git-dep
# outputHashes to maintain. To bump: update rev + version, set cargoHash = "",
# build, paste the reported sha256.
{
  pkgs,
  rustToolchain,
  lib,
}:
let
  rev = "119a84897f225c1e3213a09cd149abb37dcb3abc";
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
rustPlatform.buildRustPackage {
  pname = "buzz-cli-stack";
  version = "unstable-2026-08-09";

  src = pkgs.fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    inherit rev;
    hash = "sha256-814mVQ1R54p3yLumEK+ihREJYadcWnz/G4wNHSRo+hg=";
  };

  cargoHash = "sha256-YH2H6h7KBFil4EnHyg/rA0bLqybg3h6G+nGRmnifmB4=";

  # Build only the headless crates (and their pure-Rust deps). This skips
  # buzz-relay (needs cmake/opus), buzz-admin (pulls a git dep), and the
  # desktop/frontend (node).
  cargoBuildFlags = [
    "-p"
    "buzz-acp"
    "-p"
    "buzz-cli"
    "-p"
    "buzz-agent"
    "-p"
    "buzz-dev-mcp"
  ];

  # rustls + ring: no system TLS libs. stdenv provides the C toolchain ring needs.
  nativeBuildInputs = [ ];
  buildInputs = [ ];

  # The workspace's integration tests need a live relay + Postgres/Redis.
  doCheck = false;

  meta = {
    description = "Buzz headless CLI stack (buzz-acp, buzz-cli, buzz-agent)";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-acp";
  };
}
