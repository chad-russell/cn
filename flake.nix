{
  description = "Unified NixOS configurations for homelab infrastructure";

  nixConfig = {
    extra-substituters = [
      "https://numtide.cachix.org"
      "https://vicinae.cachix.org"
    ];
    extra-trusted-public-keys = [
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
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
      inputs.nixpkgs.follows = "nixpkgs";
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
      nixosConfigurations.think = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = specialArgs // { inherit username; };
        modules = [
          { nixpkgs.overlays = [ (final: prev: { slk = final.callPackage ./thinkpad/pkgs/slk/package.nix { }; }) ]; }
          ./thinkpad/hardware-configuration.nix
          ./thinkpad/configuration.nix
          nixos-hardware.nixosModules.lenovo-thinkpad-t14-intel-gen6
          { _module.args.username = username; }
          noctalia-shell.nixosModules.default
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

      # k1 — general purpose server (NixOS)
      nixosConfigurations.k1 = mkHost {
        hostname = "k1";
        extraModules = [
          ./modules/elitedesk-hardware.nix
        ];
      };

      # k2 — utility server (NixOS)
      nixosConfigurations.k2 = mkHost {
        hostname = "k2";
        extraModules = [
          ./modules/elitedesk-hardware.nix
        ];
      };

      # k3 — media server (NixOS)
      nixosConfigurations.k3 = mkHost {
        hostname = "k3";
        extraModules = [
          ./modules/elitedesk-hardware.nix
        ];
      };

      # k4 — utility server (NixOS)
      nixosConfigurations.k4 = mkHost {
        hostname = "k4";
        extraModules = [
          ./modules/elitedesk-hardware.nix
        ];
      };

      # hub — main infrastructure server
      nixosConfigurations.hub = mkHost {
        hostname = "hub";
      };

      # ── Deploy script (nix run .#deploy) ─────────────────────────
      apps.x86_64-linux.deploy = {
        type = "app";
        program = toString (
          nixpkgs.legacyPackages.x86_64-linux.writeShellScriptBin "deploy" ''
            set -euo pipefail

            if [ $# -lt 1 ]; then
              echo "Usage: nix run .#deploy -- <host> [host...]"
              echo "  Example: nix run .#deploy -- k2 k3 k4"
              echo ""
              echo "Available hosts: think k1 k2 k3 k4 hub"
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
                k1)
                  TARGET="root@192.168.20.61"
                  ;;
                k2)
                  TARGET="root@192.168.20.62"
                  ;;
                k3)
                  TARGET="root@192.168.20.63"
                  ;;
                k4)
                  TARGET="root@192.168.20.64"
                  ;;
                hub)
                  TARGET="root@192.168.20.105"
                  ;;
                *)
                  echo "Unknown host: $host"
                  exit 1
                  ;;
              esac

              if [ "$host" != "think" ]; then
                echo ">>> Deploying to $host ($TARGET)..."
                nixos-rebuild switch --flake .#$host --target-host "$TARGET" --build-host localhost "$@"
              fi

              echo ">>> $host done."
              echo ""
            done

            echo "All hosts deployed."
          ''
        );
      };

      # ── Install script (nix run .#install <host>) ────────────────
      apps.x86_64-linux.install = {
        type = "app";
        program = toString (
          nixpkgs.legacyPackages.x86_64-linux.writeShellScriptBin "install" ''
            set -euo pipefail

            if [ $# -lt 1 ]; then
              echo "Usage: nix run .#install -- <host> <ip>"
              echo "  Example: nix run .#install -- k1 192.168.20.61"
              echo ""
              echo "This runs nixos-anywhere to wipe and install NixOS."
              echo "WARNING: This will ERASE the target disk."
              exit 1
            fi

            HOST="$1"
            IP="''${2:-}"

            case "$HOST" in
              k1) IP="''${IP:-192.168.20.61}" ;;
              k2) IP="''${IP:-192.168.20.62}" ;;
              k3) IP="''${IP:-192.168.20.63}" ;;
              k4) IP="''${IP:-192.168.20.64}" ;;
              hub) IP="''${IP:-192.168.20.105}" ;;
              *)
                echo "Unknown host: $HOST"
                exit 1
                ;;
            esac

            echo ">>> Installing NixOS on $HOST ($IP)..."
            echo ">>> WARNING: This will ERASE the disk on $IP"
            read -p "Continue? [y/N] " confirm
            [ "$confirm" = "y" ] || exit 1

            nix run github:nix-community/nixos-anywhere -- --flake .#$HOST root@$IP
          ''
        );
      };
    };
}
