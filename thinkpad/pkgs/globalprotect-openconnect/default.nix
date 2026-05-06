{
  lib,
  stdenv,
  fetchzip,
  autoPatchelfHook,
  makeWrapper,
  glib,
  gtk3,
  libsoup_3,
  webkitgtk_4_1,
  glib-networking,
  openssl,
  libappindicator-gtk3,
  libxml2,
  zlib,
  lz4,
  gnutls,
  p11-kit,
  nettle,
  gmp,
  openconnect,
}:

let
  version = "2.5.2";
in
stdenv.mkDerivation rec {
  pname = "globalprotect-openconnect";
  inherit version;

  src = fetchzip {
    url = "https://github.com/yuezk/GlobalProtect-openconnect/releases/download/v${version}/globalprotect-openconnect_${version}_x86_64.bin.tar.xz";
    hash = "sha256-0000000000000000000000000000000000000000000000000000";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  buildInputs = [
    glib
    gtk3
    libsoup_3
    webkitgtk_4_1
    glib-networking
    openssl
    libxml2
    zlib
    lz4
    gnutls
    p11-kit
    nettle
    gmp
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share $out/libexec

    cp bin/gpclient $out/bin/
    cp bin/gpservice $out/bin/
    cp bin/gpauth $out/bin/
    cp bin/gpgui $out/bin/
    chmod +x $out/bin/*

    # Copy libexec helpers
    cp -r libexec/gpclient $out/libexec/ 2>/dev/null || true

    # Copy desktop file
    cp -r share/applications $out/share/ 2>/dev/null || true
    cp -r share/polkit-1 $out/share/ 2>/dev/null || true

    # Fix hardcoded paths
    substituteInPlace $out/bin/* \
      --replace-fail /usr/libexec/gpclient $out/libexec/gpclient 2>/dev/null || true
    substituteInPlace $out/share/applications/gpgui.desktop \
      --replace-fail /usr/bin/gpclient $out/bin/gpclient 2>/dev/null || true

    # Wrap gpclient to find openconnect and glib-networking
    wrapProgram $out/bin/gpclient \
      --prefix PATH : ${lib.makeBinPath [ openconnect ]} \
      --prefix GIO_EXTRA_MODULES : ${glib-networking}/lib/gio/modules

    runHook postInstall
  '';

  meta = with lib; {
    description = "GlobalProtect VPN client for Linux based on OpenConnect";
    homepage = "https://github.com/yuezk/GlobalProtect-openconnect";
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
