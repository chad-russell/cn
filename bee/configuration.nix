{ config, pkgs, ... }:

{
  imports = [
    ../modules/niri-desktop.nix
  ];

  # Set hostname
  networking.hostName = "bee";

  # Enable Niri desktop
  desktop.niri.enable = true;

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use the latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable zram swap
  zramSwap.enable = true;

  # Enable systemd-networkd for network management
  systemd.network.enable = true;
  networking.useDHCP = false;

  # Configure network interface with static IP
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.105/24" ];
    routes = [
      { Gateway = "192.168.20.1"; }
    ];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # Enable the OpenSSH server
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  # Enable passwordless sudo for wheel group members
  security.sudo.wheelNeedsPassword = false;

  # Define root user with SSH key access (for nixos-anywhere)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDsHOYNAog8L5SAhKp551g4oJFSi/GB+Fg38mmBLhwbrCUSfVSFqKeaOuRlLCQVnTWPZYfyp6cTibHBeigky6fjKhQgKnUJgwPdHjxhSvk7m6zgGj71s45bFT918E1J8hysN2wrijoo6oJ1zSeX3FIWOcFZVR4MHxCdYCMr+4mJp8tb1oQRea6GxCFGCms7DoNii+gWL/K2KZTMHKZ6l9Nf5CXq/6+a9Pfog3XuRlpTxLlIVj8YMC8TeRki0m9mG4+gk4OtCzACL/ngY0OxRWN4IN0NhFZOO5FHwytMR9/yNiAzafzaIt2szd69nmPG3DrXSUN1nXZKR78kM5O1kIaEKNeWJjhTXuDF7DtMF61TlXDWmsFxQbF9TAWK7nXJMUzAgXY1vIkTiYV3uwBB9upyKmXD/M5U1cFDvY6sSnINHxaqXp7/IoEHsXzHKmR5yhGLVszMzMlINBTxrWEYbjzNJPEvWeLCt3EbU4LPVffc8MA+l9zujSDjMO78uC7k/Ek= chadrussell@Chads-MacBook-Pro.local"
  ];

  # Define your user account
  users.users.crussell = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDsHOYNAog8L5SAhKp551g4oJFSi/GB+Fg38mmBLhwbrCUSfVSFqKeaOuRlLCQVnTWPZYfyp6cTibHBeigky6fjKhQgKnUJgwPdHjxhSvk7m6zgGj71s45bFT918E1J8hysN2wrijoo6oJ1zSeX3FIWOcFZVR4MHxCdYCMr+4mJp8tb1oQRea6GxCFGCms7DoNii+gWL/K2KZTMHKZ6l9Nf5CXq/6+a9Pfog3XuRlpTxLlIVj8YMC8TeRki0m9mG4+gk4OtCzACL/ngY0OxRWN4IN0NhFZOO5FHwytMR9/yNiAzafzaIt2szd69nmPG3DrXSUN1nXZKR78kM5O1kIaEKNeWJjhTXuDF7DtMF61TlXDWmsFxQbF9TAWK7nXJMUzAgXY1vIkTiYV3uwBB9upyKmXD/M5U1cFDvY6sSnINHxaqXp7/IoEHsXzHKmR5yhGLVszMzMlINBTxrWEYbjzNJPEvWeLCt3EbU4LPVffc8MA+l9zujSDjMO78uC7k/Ek= chadrussell@Chads-MacBook-Pro.local"
    ];
    hashedPassword = "$6$HG8zp6H0V/NAQJbw$CkWKAqc8nU4BdshhBXg9SczhrVNLQqu2tLAozAfgMEfXopUOyo8pdp8k13oQLpiPJqzASjdOj1Bi2fIfnMFjK1";
  };

  # Set your time zone
  time.timeZone = "America/New_York";

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # Basic packages
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    gh
  ];

  environment.sessionVariables = {
    XDG_DATA_DIRS = [ "/var/lib/flatpak/exports/share:$XDG_DATA_DIRS" ];
  };

  # Enable Flatpak
  services.flatpak.enable = true;
  
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

  # Enable Docker (needed for distrobox)
  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = true;
  
  # Enable Podman as alternative
  virtualisation.podman.enable = true;
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

  # Enable experimental Nix features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Required by NixOS
  system.stateVersion = "25.05";
}

