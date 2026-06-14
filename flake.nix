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
    nixpkgs-2605.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-bambu.url = "github:NixOS/nixpkgs/3dc39290654c7c595c9f3fa70c3b998ca2bd61b0";

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
      url = "github:noctalia-dev/noctalia-shell/v5";
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


  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-2605,
      nixpkgs-bambu,
      home-manager,
      disko,
      agenix,
      nixos-hardware,
      noctalia-shell,
      vicinae,
      nixvim,
      zen-browser,
      ...
    }:
    let
      # ── Shared args passed to all NixOS hosts ────────────────────
      specialArgs = {
        inherit disko agenix;
        unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };

      # Same unstable instance for home-manager extraSpecialArgs
      unstable-pkgs = specialArgs.unstable;

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
                nixpkgs.config.allowUnfree = true;
                # Shared overlay for custom packages
                nixpkgs.overlays = [
                  (final: prev: {
                    antigravity-cli = final.callPackage ./pkgs/antigravity-cli/package.nix { };
                    gloo-proxy = final.callPackage ./pkgs/gloo-proxy/package.nix { };
                  })
                ];
              }
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
      nixosConfigurations.think = nixpkgs-2605.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = specialArgs // { inherit username; unstable = unstable-pkgs; };
        modules = [
          {
            nixpkgs.config.allowUnfree = true;
            nixpkgs.overlays = [
              (final: prev: {
                slk = final.callPackage ./thinkpad/pkgs/slk/package.nix { };
                globalprotect-openconnect = final.callPackage ./thinkpad/pkgs/globalprotect-openconnect/default.nix { };
                antigravity-cli = final.callPackage ./pkgs/antigravity-cli/package.nix { };
                bambu-studio = (import nixpkgs-bambu { system = "x86_64-linux"; config.allowUnfree = true; }).bambu-studio;
              })
            ];
          }
          ./thinkpad/hardware-configuration.nix
          ./thinkpad/configuration.nix
          ./thinkpad/backup.nix

          ./modules/nebula-hosts.nix
          ./modules/nebula-client.nix
          ./modules/opencode.nix
          nixos-hardware.nixosModules.lenovo-thinkpad-t14-intel-gen6
          { _module.args.username = username; }

          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.sharedModules = [
              vicinae.homeManagerModules.default

              nixvim.homeModules.nixvim
              agenix.homeManagerModules.default
              zen-browser.homeModules.twilight
            ];
            home-manager.users.${username} = import ./thinkpad/home.nix;
            home-manager.extraSpecialArgs = {
              inherit noctalia-shell vicinae agenix;
              unstable = unstable-pkgs;
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
              unstable = unstable-pkgs;
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
              unstable = unstable-pkgs;
            };
          }
        ];
      };

      # gateway — Hetzner Cloud reverse proxy + Nebula lighthouse/relay
      nixosConfigurations.gateway = mkHost {
        hostname = "gateway";
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
echo "Available hosts: think bee bees misc nas gateway"
              exit 1
            fi

            HOSTS="$@"

            for host in $HOSTS; do
              case "$host" in
                think)
                  TARGET="think"
                  BUILD_HOST="''${THINK_BUILD_HOST:-}"
                  if [ -n "$BUILD_HOST" ]; then
                    echo ">>> Deploying to $host (local, building on $BUILD_HOST)..."
                    sudo nixos-rebuild switch --flake .#$host --build-host "$BUILD_HOST"
                  else
                    echo ">>> Deploying to $host (local)..."
                    sudo nixos-rebuild switch --flake .#$host
                  fi
                  ;;
                misc)
                  TARGET="crussell@192.168.20.42" # "crussell@10.10.0.11"
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
                gateway)
                  TARGET="root@178.156.171.212"
                  ;;
                *)
                  echo "Unknown host: $host"
                  exit 1
                  ;;
              esac

              if [ "$host" != "think" ]; then
                echo ">>> Deploying to $host ($TARGET)..."
                DEPLOY_ARGS="--flake .#$host --target-host $TARGET --build-host localhost --sudo"
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
              gateway) IP="''${IP:-178.156.171.212}" ;;
              *)
                echo "Unknown host: $HOST"
                exit 1
                ;;
            esac

            echo ">>> Installing NixOS on $HOST ($IP)..."
            echo ">>> WARNING: This will ERASE the disk on $IP"
            read -p "Continue? [y/N] " confirm
            [ "$confirm" = "y" ] || exit 1

# bee/bees connect as crussell; all others connect as root
            case "$HOST" in
              bee|bees)  SSH_USER="crussell" ;;
              *)         SSH_USER="root" ;;
            esac

            nix run github:nix-community/nixos-anywhere -- --flake .#$HOST $SSH_USER@$IP
          ''
        }/bin/install";
      };
    };
}
