{ config, pkgs, ... }:

{
  # Enable Flatpak
  services.flatpak.enable = true;
  
  # Set session variables for Flatpak
  environment.sessionVariables = {
    XDG_DATA_DIRS = [ "/var/lib/flatpak/exports/share:$XDG_DATA_DIRS" ];
  };
  
  # Add Flathub repository
  systemd.services.flatpak-add-flathub = {
    description = "Add Flathub remote to Flatpak";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo";
    };
  };
}

