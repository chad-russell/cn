{
  lib,
  buildGoModule,
  fetchFromGitHub,
  wl-clipboard,
}:

buildGoModule rec {
  pname = "slk";
  version = "0.6.3";

  src = fetchFromGitHub {
    owner = "gammons";
    repo = "slk";
    rev = "v${version}";
    hash = "sha256-agUaNtLlYC84lTtlR1GePwcFR7YJWPtS07N1R9pmIqo=";
  };

  vendorHash = "sha256-V9krsFhG0WJ23rGBj57fOAOd2MpLtrmAbUqFA5dS4tE=";

  # CGO disabled — pure Go build. The X11 clipboard path in
  # golang.design/x/clipboard is not needed under Wayland (niri);
  # wl-clipboard is used instead at runtime.
  env.CGO_ENABLED = "0";

  subPackages = [ "cmd/slk" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
    "-X main.commit=v${version}"
  ];

  # wl-clipboard provides wl-paste, which slk shells out to for
  # Ctrl+V image/file paste on Wayland sessions.
  runtimeDependencies = [ wl-clipboard ];

  meta = with lib; {
    description = "Blazingly fast Slack TUI client";
    homepage = "https://github.com/gammons/slk";
    license = licenses.mit;
    mainProgram = "slk";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
