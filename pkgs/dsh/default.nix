# ── @deepseek-ai/dsh (DeepSeek Harness) ──────────────────────────────
#
# Official npm distribution of DeepSeek Harness — an "everything is a
# plugin" agent harness (TypeScript, Cordis framework). The npm package
# ships PREBUILT bundles in lib/ (no build step, no postinstall), so
# packaging is: fetch tarball → npm install deps from the committed
# lockfile → wrap bin.
#
# Not in nixpkgs (checked 2026-08); no official OCI image exists. This
# package + the committed package-lock.json is our pinned dependency
# set. Bump: change version below, regenerate the lockfile with
#   npx npm@10 install --package-lock-only --ignore-scripts
# in the tarball dir, commit both together.

{ lib
, buildNpmPackage
, fetchurl
}:

buildNpmPackage rec {
  pname = "dsh";
  # npm scope dir must match: @deepseek-ai/dsh
  packageName = "@deepseek-ai/dsh";
  version = "0.1.0-rc.7";

  src = fetchurl {
    url = "https://registry.npmjs.org/${packageName}/-/dsh-${version}.tgz";
    hash = "sha256-L48Ldj1hGsU296lBHuQ8CvwGfBuHMsMQLATb45i8rMU=";
  };

  # Generated via npm install --package-lock-only (see header comment).
  # The npm tarball ships no lockfile; inject ours in postPatch.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-iGfbvMoG71r+zXZ9cvesqmHvAP1dV7ionxPk3GK3xbI=";

  # Prebuilt distribution — no compile step, no scripts to run.
  npmInstallFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  postInstall = ''
    # bin already points at lib/bin.js; ensure executable
    chmod +x $out/lib/node_modules/${packageName}/lib/bin.js
  '';

  meta = with lib; {
    description = "DeepSeek Harness: open-source agent harness (everything is a plugin)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    mainProgram = "dsh";
    platforms = platforms.linux;
  };
}
