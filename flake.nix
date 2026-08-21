{
  description = "Unified NixOS configurations for homelab infrastructure";

  inputs = {
    # ── Nixpkgs ────────────────────────────────────────────────────
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # ── Home Manager ───────────────────────────────────────────────
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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

    # ── Hermes Agent (gateway on bee) ─────────────────────────────
    # Does NOT follow our nixpkgs: Hermes needs nodejs_26 which nixos-25.11
    # doesn't ship. The module builds its own package internally.
    hermes-agent = { url = "github:NousResearch/hermes-agent"; };

    # ── Hermes WebUI (community web frontend for Hermes Agent) ────────
    # https://github.com/nesquena/hermes-webui — runs the agent in-process
    # against HERMES_HOME. Like hermes-agent, does NOT follow our nixpkgs;
    # the NixOS module derives the agent interpreter from
    # services.hermes-agent.package's passthru.hermesVenv.
    hermes-webui = { url = "github:nesquena/hermes-webui"; };

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, disko, agenix
    , hermes-agent, hermes-webui, ... }:
    let
      lib = nixpkgs.lib;
      username = "crussell";

      # ── Host metadata (single source of truth) ───────────────────
      hostMeta = import ./lib/host-meta.nix;
      deployable = lib.filterAttrs (_: h: h ? deployUser) hostMeta;

      # ── DeepSeek Harness (dsh) ────────────────────────────────────
      # Official npm dist, packaged via buildNpmPackage. Imported by
      # modules/dsh.nix (services.dsh on bee).
      dshPkg = pkgs.callPackage ./pkgs/dsh { };

      # System pkgs for callPackage above.
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };

      # Bash case bodies, generated from hostMeta so the deploy/install
      # scripts never drift from lib/host-meta.nix.
      deployCase = lib.concatStringsSep "\n" (lib.mapAttrsToList
        (n: h: "          ${n}) TARGET=\"${h.deployUser}@${h.nebula}\" ;;")
        deployable);
      installIpCase = lib.concatStringsSep "\n"
        (lib.mapAttrsToList (n: h: "          ${n}) IP=\"\${IP:-${h.lan}}\" ;;")
          deployable);
      installUserCase = lib.concatStringsSep "\n" (lib.mapAttrsToList
        (n: h: "          ${n}) SSH_USER=\"${h.installUser}\" ;;") deployable);
      availableHosts = lib.concatStringsSep " " (lib.attrNames deployable);

      # ── Shared args passed to all NixOS hosts ────────────────────
      specialArgs = {
        unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        dsh = dshPkg;
      };

      # ── Helper to build a NixOS configuration ────────────────────
      # Every host gets home-manager (consistent shell/dotfiles for
      # `crussell`); pass extraModules for host-specific extras.
      mkHost = { hostname, system ? "x86_64-linux", extraModules ? [ ]
        , extraSpecialArgs ? { }, }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = specialArgs // extraSpecialArgs;
          modules = [
            ./hosts/${hostname}/configuration.nix
            disko.nixosModules.disko
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              nixpkgs.config.allowUnfree = true;
              home-manager.useUserPackages = true;
              home-manager.useGlobalPkgs = true;
              home-manager.users.${username} = import ./modules/server-home.nix;
            }
            {
              # Make this flake self-referential for deployments
              nix.registry.cn.flake = self;
              nix.settings.experimental-features = [ "nix-command" "flakes" ];
            }
          ] ++ extraModules;
        };
    in {
      # ── NixOS Configurations ─────────────────────────────────────
      nixosConfigurations.bee = mkHost {
        hostname = "bee";
        extraModules = [
          hermes-agent.nixosModules.default
          hermes-webui.nixosModules.default
        ];
      };
      nixosConfigurations.bees = mkHost { hostname = "bees"; };
      nixosConfigurations.nas = mkHost { hostname = "nas"; };
      nixosConfigurations.gateway = mkHost { hostname = "gateway"; };

      # ── Packages ─────────────────────────────────────────────────
      packages.x86_64-linux.dsh = dshPkg;

      # ── Eval gate (nix flake check) ──────────────────────────────
      # Eval the full system toplevel for each NixOS host. Catches syntax
      # errors, option typos, and type mismatches without deploying.
      # Run with: nix flake check (or nix build .#checks.x86_64-linux.<host>)
      checks.x86_64-linux = builtins.listToAttrs (builtins.map (host: {
        name = host;
        value = self.nixosConfigurations.${host}.config.system.build.toplevel;
      }) (builtins.attrNames self.nixosConfigurations));

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
                echo "Run from the deploy origin (bees). Builds happen on this"
                echo "machine; the target is switched over SSH (or locally if it"
                echo "is this host)."
                echo ""
                echo "Available hosts: ${availableHosts}"
                exit 1
              fi

              HOSTS="$@"
              THIS_HOST="$(hostname)"

              for host in $HOSTS; do
                case "$host" in
              ${deployCase}
                  *)
                    echo "Unknown host: $host" >&2
                    exit 1
                    ;;
                esac

                if [ "$host" = "$THIS_HOST" ]; then
                  echo ">>> Deploying to $host (local)..."
                  sudo nixos-rebuild switch --flake .#$host
                else
                  echo ">>> Deploying to $host ($TARGET)..."
                  nixos-rebuild switch --flake .#$host --target-host "$TARGET" --sudo
                fi

                echo ">>> $host done."
                echo ""
              done

              echo "All hosts deployed."
            ''
          }/bin/deploy";
      };

      # ── Install script (nix run .#install <host>) ────────────────
      # Destructive: runs nixos-anywhere to wipe and install NixOS.
      # Requires an explicit --i-understand-this-wipes-the-disk flag so
      # agents (and humans) can't confuse it with `deploy`.
      apps.x86_64-linux.install = {
        type = "app";
        program = "${
            nixpkgs.legacyPackages.x86_64-linux.writeShellScriptBin "install" ''
              set -euo pipefail

              CONFIRM_FLAG="--i-understand-this-wipes-the-disk"

              # Filter out the confirm flag from positional args
              ARGS=()
              CONFIRMED=false
              for arg in "$@"; do
                if [ "$arg" = "$CONFIRM_FLAG" ]; then
                  CONFIRMED=true
                else
                  ARGS+=("$arg")
                fi
              done
              set -- "''${ARGS[@]}"

              if [ $# -lt 1 ] || [ "$CONFIRMED" = false ]; then
                echo "Usage: nix run .#install -- <host> <ip> $CONFIRM_FLAG"
                echo "  Example: nix run .#install -- bees 192.168.20.41 $CONFIRM_FLAG"
                echo ""
                echo "Runs nixos-anywhere to WIPE the target disk and install NixOS."
                echo "The $CONFIRM_FLAG flag is MANDATORY."
                echo ""
                echo "Available hosts: ${availableHosts}"
                exit 1
              fi

              HOST="$1"
              IP="''${2:-}"

              case "$HOST" in
              ${installIpCase}
                *)
                  echo "Unknown host: $HOST" >&2
                  exit 1
                  ;;
              esac

              echo ">>> Installing NixOS on $HOST ($IP)..."
              echo ">>> WARNING: This will ERASE the disk on $IP"

              case "$HOST" in
              ${installUserCase}
              esac

              nix run github:nix-community/nixos-anywhere -- --flake .#$HOST $SSH_USER@$IP
            ''
          }/bin/install";
      };
    };
}
