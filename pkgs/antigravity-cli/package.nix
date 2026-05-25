{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  # ── How to update antigravity-cli ──────────────────────────────────
  #
  # The upstream binary is a self-updating Go binary, but since Nix store
  # paths are read-only, the auto-updater cannot work. Updates must be
  # done manually by editing the three values below.
  #
  # Steps:
  #
  #   1. Fetch the latest release manifest:
  #        curl -fsSL https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json | jq .
  #
  #      This returns JSON like:
  #        {
  #          "version": "1.2.3",
  #          "url": "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.2.3-XXXXXXXXXXXXXXXX/linux-x64/cli_linux_x64.tar.gz",
  #          "sha512": "..."
  #        }
  #
  #   2. Update `version` below to the version string from the manifest.
  #
  #   3. Update `buildId` below to the numeric ID embedded in the URL
  #      (the part after the version, e.g. "5288553236791296").
  #
  #   4. Replace the `hash` value with an empty string (""), then attempt
  #      a build:
  #        nix-build -E 'with import <nixpkgs> {}; callPackage ./pkgs/antigravity-cli/package.nix {}' \
  #          --option allow-unfree true
  #
  #      Nix will fail with the correct hash. Copy that hash into the
  #      `hash` field below.
  #
  #   5. Verify the build succeeds, then deploy:
  #        nix run .#deploy -- think bee bees
  #
  # Alternatively, if the manifest URL changes or is unreachable, the
  # binary can be downloaded manually from:
  #   curl -fsSL https://antigravity.google/cli/install.sh | bash
  # and the installed binary found at ~/.local/bin/agy
  #
  version = "1.0.0";
  buildId = "5288553236791296";
in
stdenv.mkDerivation rec {
  pname = "antigravity-cli";
  inherit version;

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-${buildId}/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha256-cAljQFdPr8SgbE08gFcxTiLUdc4cgg0K1R/wf7fpnrY=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook ];

  # Go binary — statically linked but may reference glibc for DNS resolution.
  # autoPatchelfHook will add needed rpath if required.
  buildInputs = [ stdenv.cc.cc.lib ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 antigravity $out/bin/agy
    runHook postInstall
  '';

  meta = with lib; {
    description = "Google Antigravity CLI — agentic coding TUI (successor to Gemini CLI)";
    homepage = "https://antigravity.google/docs/cli-overview";
    license = licenses.unfree;
    mainProgram = "agy";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
