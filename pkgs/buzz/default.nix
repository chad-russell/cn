# ── Buzz CLI stack: buzz-acp + buzz-cli + buzz-agent ────────────────────
#
# Builds three headless Rust binaries from upstream block/buzz. These are
# pure-Rust (rustls/ring TLS — no openssl), and do NOT build buzz-relay, so the
# cmake/opus toolchain the relay needs is avoided entirely. buzz-admin is
# intentionally excluded: it pulls buzz-media → rust-s3 (a git dep); mint agent
# keypairs with `nak` instead (see GUIDES/DEPLOY_BUZZ_HARNESS_ON_BEE.md).
#
# Toolchain is pinned to the exact version from upstream rust-toolchain.toml
# (1.95.0), which is newer than nixos-25.11 ships — hence the passed-in
# rustToolchain (built from rust-overlay in flake.nix).
{
  pkgs,
  rustToolchain,
  lib,
}:
let
  rev = "10d5a26414dc90dc89fd27de74b21e105d4fa622";
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
rustPlatform.buildRustPackage {
  pname = "buzz-cli-stack";
  version = "unstable-2026-07-31";

  src = pkgs.fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    inherit rev;
    hash = "sha256-wmcZXyfHClBbKBG1HPVJcKPvY/kbigS/YNyUPepU3JI=";
  };

  # The full workspace lockfile vendors every git dep regardless of which
  # packages we compile, so both upstream git crates need outputHashes:
  #   aws-creds (patched crates-io dep via buzz-media → rust-s3)
  #   mesh-llm-api-client (buzz-relay-mesh / shared compute)
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "aws-creds-0.39.1" = "sha256-QAAm1phmeLFtDRgfDCoHijN1ce/rYzh18KziOUbL+hw=";
      "mesh-llm-api-client-0.74.0" = "sha256-nkt/bTHvc7ACAP2Gx/Px/hGad5ryzWn2eA9isXKF05s=";
    };
  };

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
