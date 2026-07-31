# ── Buzz CLI stack: buzz-acp + buzz-cli + buzz-agent + buzz-admin ───────
#
# Builds four headless Rust binaries from upstream block/buzz. These are
# pure-Rust (rustls/ring TLS — no openssl), and do NOT build buzz-relay, so the
# cmake/opus toolchain the relay needs is avoided entirely. buzz-admin's DB ops
# need Postgres only at runtime; `buzz-admin generate-key` needs nothing extra.
#
# Toolchain is pinned to the exact version from upstream rust-toolchain.toml
# (1.95.0), which is newer than nixos-25.11 ships — hence the passed-in
# rustToolchain (built from rust-overlay in flake.nix).
#
# On first build, two git deps in the upstream Cargo.lock need outputHashes.
# nix will print the expected sha256 on the failed fixed-output derivation;
# paste each into `outputHashes` below. See PLANS/BUZZ_HARNESS_ON_BEE.md.
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
    # Fill from the first build's fixed-output failure.
    hash = lib.fakeHash;
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    # Two upstream git deps. Replace lib.fakeHash with the sha256 nix reports.
    outputHashes = {
      "https://github.com/Mesh-LLM/mesh-llm.git?tag=v0.74.0" = lib.fakeHash;
      "https://github.com/tlongwell-block/rust-s3?rev=c9fce3620dd434c1f810101d672cf384268dbb0f" =
        lib.fakeHash;
    };
  };

  # Build only the headless crates (and their pure-Rust deps). This skips
  # buzz-relay (needs cmake/opus) and the desktop/frontend (node). buzz-admin
  # is included for `buzz-admin generate-key` (minting agent identities).
  cargoBuildFlags = [
    "-p"
    "buzz-acp"
    "-p"
    "buzz-cli"
    "-p"
    "buzz-agent"
    "-p"
    "buzz-admin"
  ];

  # rustls + ring: no system TLS libs. stdenv provides the C toolchain ring needs.
  nativeBuildInputs = [ ];
  buildInputs = [ ];

  # The workspace's integration tests need a live relay + Postgres/Redis.
  doCheck = false;

  meta = {
    description = "Buzz headless CLI stack (buzz-acp, buzz-cli, buzz-agent, buzz-admin)";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-acp";
  };
}
