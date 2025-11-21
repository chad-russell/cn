{ config, pkgs, ... }:

{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Pin the kernel to a stable LTS version to avoid the e1000e driver bug.
  boot.kernelPackages = pkgs.linuxPackages_6_6;

  # Enable zram swap.
  zramSwap.enable = true;

  # Enable systemd-networkd for network management
  systemd.network.enable = true;
  networking.useDHCP = false;

  # Enable the OpenSSH server.
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password"; # Allow root login with SSH keys only

  # Enable the Cockpit web UI.
  services.cockpit.enable = true;

  # Enable Tailscale
  services.tailscale.enable = true;
  # To connect to Tailscale, run: sudo tailscale up
  # You'll get a URL to authenticate with your Tailscale account

  # Enable Docker
  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = true;
  virtualisation.docker.daemon.settings = {
    # Optional: Configure Docker daemon settings
    # log-driver = "json-file";
    # log-opts = {
    #   max-size = "10m";
    #   max-file = "3";
    # };
  };

  # Use Docker for OCI containers (more reliable DNS than Podman)
  virtualisation.oci-containers.backend = "docker";

  # Enable Podman
  virtualisation.podman.enable = true;
  # Note: dockerSocket.enable conflicts with Docker, so we'll use Docker as primary
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;
  virtualisation.podman.extraPackages = [ pkgs.aardvark-dns ];

  # Enable passwordless sudo for wheel group members (prevents lockout)
  security.sudo.wheelNeedsPassword = false;

  # Define root user with SSH key access (for nixos-anywhere and emergency access)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDsHOYNAog8L5SAhKp551g4oJFSi/GB+Fg38mmBLhwbrCUSfVSFqKeaOuRlLCQVnTWPZYfyp6cTibHBeigky6fjKhQgKnUJgwPdHjxhSvk7m6zgGj71s45bFT918E1J8hysN2wrijoo6oJ1zSeX3FIWOcFZVR4MHxCdYCMr+4mJp8tb1oQRea6GxCFGCms7DoNii+gWL/K2KZTMHKZ6l9Nf5CXq/6+a9Pfog3XuRlpTxLlIVj8YMC8TeRki0m9mG4+gk4OtCzACL/ngY0OxRWN4IN0NhFZOO5FHwytMR9/yNiAzafzaIt2szd69nmPG3DrXSUN1nXZKR78kM5O1kIaEKNeWJjhTXuDF7DtMF61TlXDWmsFxQbF9TAWK7nXJMUzAgXY1vIkTiYV3uwBB9upyKmXD/M5U1cFDvY6sSnINHxaqXp7/IoEHsXzHKmR5yhGLVszMzMlINBTxrWEYbjzNJPEvWeLCt3EbU4LPVffc8MA+l9zujSDjMO78uC7k/Ek= chadrussell@Chads-MacBook-Pro.local"
  ];

  # Define your user account.
  users.users.crussell = {
    isNormalUser = true;
    # Add user to the 'wheel' group to grant sudo privileges.
    extraGroups = [ "wheel" "docker" ];
    # CRITICAL: Add your SSH public key here to ensure you can log in.
    openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDsHOYNAog8L5SAhKp551g4oJFSi/GB+Fg38mmBLhwbrCUSfVSFqKeaOuRlLCQVnTWPZYfyp6cTibHBeigky6fjKhQgKnUJgwPdHjxhSvk7m6zgGj71s45bFT918E1J8hysN2wrijoo6oJ1zSeX3FIWOcFZVR4MHxCdYCMr+4mJp8tb1oQRea6GxCFGCms7DoNii+gWL/K2KZTMHKZ6l9Nf5CXq/6+a9Pfog3XuRlpTxLlIVj8YMC8TeRki0m9mG4+gk4OtCzACL/ngY0OxRWN4IN0NhFZOO5FHwytMR9/yNiAzafzaIt2szd69nmPG3DrXSUN1nXZKR78kM5O1kIaEKNeWJjhTXuDF7DtMF61TlXDWmsFxQbF9TAWK7nXJMUzAgXY1vIkTiYV3uwBB9upyKmXD/M5U1cFDvY6sSnINHxaqXp7/IoEHsXzHKmR5yhGLVszMzMlINBTxrWEYbjzNJPEvWeLCt3EbU4LPVffc8MA+l9zujSDjMO78uC7k/Ek= chadrussell@Chads-MacBook-Pro.local"
    ];
    # Enable password login - you need to set a hashed password
    # To generate a hashed password, run: mkpasswd -m SHA-512
    # Then replace the placeholder below with your hashed password
    hashedPassword = "$6$HG8zp6H0V/NAQJbw$CkWKAqc8nU4BdshhBXg9SczhrVNLQqu2tLAozAfgMEfXopUOyo8pdp8k13oQLpiPJqzASjdOj1Bi2fIfnMFjK1";
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Install git package
  environment.systemPackages = with pkgs; [
    git
  ];

  # Enable experimental Nix features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # This is required by NixOS.
  system.stateVersion = "25.05";
}

