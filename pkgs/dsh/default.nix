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

{ lib, bashInteractive, buildNpmPackage, fetchurl, makeWrapper, nodejs }:

buildNpmPackage rec {
  pname = "dsh";
  # npm scope dir must match: @deepseek-ai/dsh
  packageName = "@deepseek-ai/dsh";
  version = "0.2.0-rc.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/${packageName}/-/dsh-${version}.tgz";
    hash = "sha256-vSeEfERc1opWWsH5HAa7vMdjnvkwcfZ4u1nF66/ziFk=";
  };

  # Generated via npm install --package-lock-only (see header comment).
  # The npm tarball ships no lockfile; inject ours in postPatch.
  # 0.1.5 declared devDependencies on unpublished experimental packages
  # (e.g. @deepseek-ai/dsh-experimental-code-runtime-python -> 404); the
  # prebuilt dist needs only the production tree, so strip devDeps at
  # build time and ship a prod-only lockfile (0.2.0-rc.2's tarball ships
  # no devDependencies at all, so the strip is now a harmless no-op;
  # lockfile regenerated 2026-10-01 the same way).
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    # 0.1.5 declares devDependencies on unpublished experimental packages
    # (e.g. @deepseek-ai/dsh-experimental-code-runtime-python -> registry
    # 404). The prebuilt dist needs only the production tree, so we ship
    # a prod-only lockfile (generated 2026-09-11 via `npm install
    # --package-lock-only` over a dev-stripped package.json) and strip
    # devDependencies here. sed/awk only — this postPatch also runs in
    # the npm-deps fetcher derivation, which has no node/python on PATH.
    sed '/^  "devDependencies": {/,/^  }/d' package.json | awk '
      prev ~ /,$/ && $0 ~ /^}/ { sub(/,$/, "", prev) }
      { if (prev != "") print prev; prev = $0 }
      END { print prev }' > package.json.stripped
    mv package.json.stripped package.json
  '';

  npmDepsHash = "sha256-80NndyRPP6EsLOgT+73No/ln3GrpcvbFW+/CRFpNTa8=";

  # Prebuilt distribution — no compile step, no scripts to run.
  npmInstallFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  # dsh 0.2.0 boots its plugin resolver through node-addon-require-builtin,
  # a native addon whose runtime machine-code probe only recognizes
  # official nodejs.org builds — it aborts every nixpkgs-built Node at boot
  # (nixpkgs#565667, deepseek-harness discussion #1873):
  #   "Unsupported/no-getter (x64 sysv getter is not a recognized ...)".
  # Restore upstream's own pre-0.2.0 behavior (vendor/loader internal.ts):
  # when --expose-internals is in argv (our wrapper always adds it), plain
  # require() of the internal module works on ANY Node build — the native
  # addon stays as the flag-less fallback. Patches the single wrapper every
  # call site funnels through (app-boot + worker bootstrap). Single-line
  # pattern/replacement: nix '' strings mangle multi-line patterns
  # (indent stripping; plain \n is a literal backslash-n).
  postInstall = ''
    # bin already points at lib/bin.js; ensure executable
    chmod +x $out/lib/node_modules/${packageName}/lib/bin.js

    substituteInPlace $out/lib/node_modules/${packageName}/node_modules/node-addon-require-builtin/lib/index.js \
      --replace-fail 'return api.requireBuiltin(moduleId);' 'if (process.execArgv.includes("--expose-internals")) { try { return require(moduleId); } catch {} } return api.requireBuiltin(moduleId);'

    # NixOS has no /bin/bash (numtide/llm-agents.nix issue #8086) — terminal
    # sessions would fail to spawn.
    substituteInPlace $out/lib/node_modules/${packageName}/node_modules/@deepseek-ai/dsh-terminal-bash/lib/index.js \
      --replace-fail '"/bin/bash"' '"${lib.getExe bashInteractive}"'
  '';

  # `dsh web` requires Node's --expose-internals flag (the Cordis HMR
  # plugin inspects V8 internals). Node refuses that flag in
  # NODE_OPTIONS, so the only reliable injection point is argv: replace
  # npm's bin symlink with a wrapper that execs node with the flag.
  postFixup = ''
    rm "$out/bin/dsh"
    makeWrapper "${nodejs}/bin/node" "$out/bin/dsh" \
      --add-flags "--expose-internals $out/lib/node_modules/${packageName}/lib/bin.js"
  '';

  meta = with lib; {
    description =
      "DeepSeek Harness: open-source agent harness (everything is a plugin)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    mainProgram = "dsh";
    platforms = platforms.linux;
  };
}
