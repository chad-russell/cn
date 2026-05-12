{
  description = "Unified NixOS configurations for homelab infrastructure";

  nixConfig = {
    extra-substituters = [
      "https://numtide.cachix.org"
      "https://vicinae.cachix.org"
      "https://noctalia.cachix.org"
    ];
    extra-trusted-public-keys = [
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  inputs = {
    # ── Nixpkgs ────────────────────────────────────────────────────
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # ── Home Manager ───────────────────────────────────────────────
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Disk partitioning ──────────────────────────────────────────
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # ── Secret management ──────────────────────────────────────────
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # ── Thinkpad-specific ──────────────────────────────────────────
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    noctalia-shell = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    vicinae.url = "github:vicinaehq/vicinae";
    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # ── Hyprland (Wayland compositor, Lua config from 0.55+) ───────
    hyprland.url = "github:hyprwm/Hyprland/v0.55.0";

    # ── Mango (Wayland compositor, dwm-like with scroll layout) ────
    mango = {
      url = "github:mangowm/mango";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      disko,
      agenix,
      nixos-hardware,
      noctalia-shell,
      vicinae,
      nixvim,
      zen-browser,
      hyprland,
      mango,
      ...
    }:
    let
      # ── Shared args passed to all NixOS hosts ────────────────────
      specialArgs = {
        inherit disko agenix;
        unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
      };

      # ── Helper to build a NixOS configuration ────────────────────
      mkHost =
        {
          hostname,
          system ? "x86_64-linux",
          extraModules ? [ ],
          extraSpecialArgs ? { },
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = specialArgs // extraSpecialArgs;
          modules =
            [
              ./hosts/${hostname}/configuration.nix
              disko.nixosModules.disko
              agenix.nixosModules.default
              {
                # Make this flake self-referential for deployments
                nix.registry.cn.flake = self;
                nix.settings.experimental-features = [
                  "nix-command"
                  "flakes"
                ];
              }
            ]
            ++ extraModules;
        };

      username = "crussell";
    in
    {
      # ── NixOS Configurations ─────────────────────────────────────

      # Thinkpad — has its own directory structure (home-manager, pkgs, etc.)
      nixosConfigurations.think = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = specialArgs // { inherit username; inherit hyprland; };
        modules = [
          {
            nixpkgs.overlays = [
              (final: prev: {
                slk = final.callPackage ./thinkpad/pkgs/slk/package.nix { };
                globalprotect-openconnect = final.callPackage ./thinkpad/pkgs/globalprotect-openconnect/default.nix { };
              })
            ];
          }
          ./thinkpad/hardware-configuration.nix
          ./thinkpad/configuration.nix
          ./thinkpad/backup.nix
          ./modules/nebula-hosts.nix
          nixos-hardware.nixosModules.lenovo-thinkpad-t14-intel-gen6
          { _module.args.username = username; }
          hyprland.nixosModules.default
          mango.nixosModules.mango
          noctalia-shell.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.sharedModules = [
              vicinae.homeManagerModules.default
              mango.hmModules.mango
              nixvim.homeModules.nixvim
              agenix.homeManagerModules.default
              zen-browser.homeModules.twilight
            ];
            home-manager.users.${username} = import ./thinkpad/home.nix;
            home-manager.extraSpecialArgs = {
              inherit noctalia-shell vicinae agenix hyprland;
            };
          }
          disko.nixosModules.disko
          agenix.nixosModules.default
          {
            nix.registry.cn.flake = self;
            nix.settings.experimental-features = [ "nix-command" "flakes" ];
          }
        ];
      };

      # bee — Beelink mini PC (general-purpose server)
      nixosConfigurations.bee = mkHost {
        hostname = "bee";
        extraModules = [
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.sharedModules = [
              nixvim.homeModules.nixvim
            ];
            home-manager.users.${username} = import ./modules/server-home.nix;
            home-manager.extraSpecialArgs = {
              unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
            };
          }
        ];
      };

      # misc — HP Z820 workstation (temporary backup target, future hypervisor)
      nixosConfigurations.misc = mkHost {
        hostname = "misc";
      };

      # nas — UGREEN DXP4800 Pro (network-attached storage, btrfs RAID1)
      nixosConfigurations.nas = mkHost {
        hostname = "nas";
      };

      # bees — AMD Ryzen AI MAX+ 395 production server
      nixosConfigurations.bees = mkHost {
        hostname = "bees";
        extraModules = [
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.sharedModules = [
              nixvim.homeModules.nixvim
            ];
            home-manager.users.${username} = import ./modules/server-home.nix;
            home-manager.extraSpecialArgs = {
              unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
            };
          }
        ];
      };

      # ── Deploy script (nix run .#deploy) ─────────────────────────
      apps.x86_64-linux.deploy = {
        type = "app";
        program = "${
          nixpkgs.legacyPackages.x86_64-linux.writeShellScriptBin "deploy" ''
            set -euo pipefail

            if [ $# -lt 1 ]; then
              echo "Usage: nix run .#deploy -- <host> [host...]"
              echo "  Example: nix run .#deploy -- bee bees"
              echo ""
              echo "Available hosts: think bee bees misc nas"
              exit 1
            fi

            HOSTS="$@"

            for host in $HOSTS; do
              case "$host" in
                think)
                  TARGET="think"
                  # Local machine — just rebuild
                  echo ">>> Deploying to $host (local)..."
                  sudo nixos-rebuild switch --flake .#$host
                  ;;
                misc)
                  TARGET="crussell@10.10.0.11"
                  ;;
                nas)
                  TARGET="crussell@10.10.0.3"
                  ;;
                bee)
                  TARGET="crussell@10.10.0.12"
                  ;;
                bees)
                  TARGET="crussell@10.10.0.6"
                  ;;
                *)
                  echo "Unknown host: $host"
                  exit 1
                  ;;
              esac

              if [ "$host" != "think" ]; then
                echo ">>> Deploying to $host ($TARGET)..."
                DEPLOY_ARGS="--flake .#$host --target-host $TARGET --build-host localhost"
                if [ "$host" = "bee" ] || [ "$host" = "bees" ] || [ "$host" = "misc" ] || [ "$host" = "nas" ]; then
                  DEPLOY_ARGS="$DEPLOY_ARGS --sudo"
                fi
                nixos-rebuild switch $DEPLOY_ARGS
              fi

              echo ">>> $host done."
              echo ""
            done

            echo "All hosts deployed."
          ''
        }/bin/deploy";
      };

      # ── Install script (nix run .#install <host>) ────────────────
      apps.x86_64-linux.install = {
        type = "app";
        program = "${
          nixpkgs.legacyPackages.x86_64-linux.writeShellScriptBin "install" ''
            set -euo pipefail

            if [ $# -lt 1 ]; then
              echo "Usage: nix run .#install -- <host> <ip>"
              echo "  Example: nix run .#install -- bees 192.168.20.41"
              echo ""
              echo "This runs nixos-anywhere to wipe and install NixOS."
              echo "WARNING: This will ERASE the target disk."
              exit 1
            fi

            HOST="$1"
            IP="''${2:-}"

            case "$HOST" in
              bee) IP="''${IP:-192.168.20.105}" ;;
              bees) IP="''${IP:-192.168.20.41}" ;;
              misc) IP="''${IP:-192.168.20.42}" ;;
              nas) IP="''${IP:-192.168.20.31}" ;;
              *)
                echo "Unknown host: $HOST"
                exit 1
                ;;
            esac

            echo ">>> Installing NixOS on $HOST ($IP)..."
            echo ">>> WARNING: This will ERASE the disk on $IP"
            read -p "Continue? [y/N] " confirm
            [ "$confirm" = "y" ] || exit 1

            # nixos-anywhere always connects as root (installer has no other users)
            SSH_USER="root"

            nix run github:nix-community/nixos-anywhere -- --flake .#$HOST $SSH_USER@$IP
          ''
        }/bin/install";
      };
    };
}
