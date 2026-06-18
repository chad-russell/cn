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
    hash = "sha256-48K1aN5Rp79mrPAy8MqnqLMbklH9/0HBSOV3CbjCgO0=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  buildInputs = [
    glib
    gtk3
    libsoup_3
    webkitgtk_4_1
    glib-networking
    openssl
    libappindicator-gtk3
    libxml2
    zlib
    lz4
    gnutls
    p11-kit
    nettle
    gmp
    stdenv.cc.cc.lib
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # The upstream binary tarball is laid out like a distro package and expects
    # DESTDIR to stage into a filesystem tree under /usr.
    make DESTDIR=$out install

    # Expose the usual Nix top-level paths while keeping the staged /usr tree
    # intact for the upstream binaries' hardcoded fallback paths.
    ln -s usr/share $out/share
    ln -s usr/lib $out/lib
    ln -s usr/libexec $out/libexec

    mkdir -p $out/bin
    for prog in gpclient gpservice gpauth gpgui gpgui-helper; do
      if [ -e "$out/usr/bin/$prog" ]; then
        makeWrapper "$out/usr/bin/$prog" "$out/bin/$prog" \
          --prefix PATH : ${lib.makeBinPath [ openconnect ]} \
          --prefix GIO_EXTRA_MODULES : ${glib-networking}/lib/gio/modules
      fi
    done

    substituteInPlace $out/usr/share/applications/gpgui.desktop \
      --replace-fail 'Exec=/usr/bin/gpclient' 'Exec=$out/bin/gpclient'

    runHook postInstall
  '';

  meta = with lib; {
    description = "GlobalProtect VPN client for Linux based on OpenConnect";
    homepage = "https://github.com/yuezk/GlobalProtect-openconnect";
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
