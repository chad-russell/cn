{
  lib,
  stdenv,
  bun,
}:

stdenv.mkDerivation rec {
  pname = "gloo-proxy";
  version = "1.0.0";

  src = ./gloo-proxy.ts;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib

    cp $src $out/lib/gloo-proxy.ts

    cat > $out/bin/gloo-proxy << EOF
    #!/bin/sh
    exec ${bun}/bin/bun run $out/lib/gloo-proxy.ts "\$@"
    EOF
    chmod +x $out/bin/gloo-proxy

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenAI-compatible proxy for Gloo AI models";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "gloo-proxy";
  };
}
