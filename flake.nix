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
    # hermes-webui = { url = "github:nesquena/hermes-webui"; };  # retired 2026-09-01

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, disko, agenix
    , hermes-agent, ... }:
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

      # ── Thinkpad /etc/hosts fragment (generated, drift-guarded) ────
      # The thinkpad isn't NixOS but should resolve the same Nebula overlay
      # hostnames every server gets via modules/nebula-hosts.nix. Rendered
      # here from the SAME source + rule (lib/host-meta.nix), so fleet and
      # laptop can never drift. The rendered copy is committed at
      # hosts/thinkpad/host-image/nebula-hosts (inside the image build
      # context); `nix flake check` fails if it goes stale. Regenerate:
      #   nix run .#render-thinkpad-hosts
      thinkpadHostsHeader =
        "# --- Nebula overlay hosts (generated from lib/host-meta.nix — do not edit) ---";
      thinkpadHostsText = thinkpadHostsHeader + "\n" + lib.concatLines
        (lib.mapAttrsToList (name: h: "${h.nebula}	${h.hostsName or name}")
          hostMeta);
      # Complete /etc/hosts for the image: the stock Fedora loopback block +
      # the fragment. The image gets this via COPY (RUN can't write /etc/hosts
      # — buildah runtime-masks it, so RUN appends never commit to the layer;
      # COPY writes the layer tarball directly). At deploy time bootc turns
      # the image's /etc into /usr/etc defaults and ostree 3-way merges them
      # into the live /etc/hosts on upgrade.
      thinkpadEtcHostsText = ''
        127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
        ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

      '' + thinkpadHostsText;

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
        # bee overrides the hermes-agent package (sealed-venv provider extras
        # for the mem0 memory backend), so it needs the flake input directly.
        extraSpecialArgs = { inherit hermes-agent; };
        extraModules = [
          hermes-agent.nixosModules.default
          # hermes-webui.nixosModules.default  # retired 2026-09-01
        ];
      };
      nixosConfigurations.bees = mkHost { hostname = "bees"; };
      nixosConfigurations.nas = mkHost { hostname = "nas"; };
      nixosConfigurations.gateway = mkHost { hostname = "gateway"; };

      # ── Packages ─────────────────────────────────────────────────
      packages.x86_64-linux.dsh = dshPkg;
      # Rendered /etc/hosts fragment for the thinkpad host image (inspection:
      # nix build .#thinkpad-nebula-hosts && cat result).
      packages.x86_64-linux.thinkpad-nebula-hosts =
        pkgs.writeText "nebula-hosts" thinkpadHostsText;

      # ── Eval gate (nix flake check) ──────────────────────────────
      # Eval the full system toplevel for each NixOS host. Catches syntax
      # errors, option typos, and type mismatches without deploying.
      # Run with: nix flake check (or nix build .#checks.x86_64-linux.<host>)
      checks.x86_64-linux = (builtins.listToAttrs (builtins.map (host: {
        name = host;
        value = self.nixosConfigurations.${host}.config.system.build.toplevel;
      }) (builtins.attrNames self.nixosConfigurations))) // {
        # Drift guard: the committed thinkpad hosts fragment must match the
        # rendering of lib/host-meta.nix byte-for-byte. Fails with a diff
        # and the fix command when host-meta.nix is edited without
        # regenerating (see apps.render-thinkpad-hosts).
        thinkpad-nebula-hosts =
          if builtins.readFile ./hosts/thinkpad/host-image/nebula-hosts
          == thinkpadHostsText
          && builtins.readFile ./hosts/thinkpad/host-image/etc-hosts
          == thinkpadEtcHostsText then
            pkgs.runCommand "thinkpad-nebula-hosts" { } "touch $out"
          else
            pkgs.runCommand "thinkpad-nebula-hosts" { } ''
              echo "ERROR: thinkpad hosts files are stale against lib/host-meta.nix." >&2
              echo "Fix: nix run .#render-thinkpad-hosts && commit the result" >&2
              echo "--- committed (left) vs expected (right) ---" >&2
              diff ${./hosts/thinkpad/host-image/nebula-hosts} ${
                pkgs.writeText "expected-frag" thinkpadHostsText
              } >&2 || true
              diff ${./hosts/thinkpad/host-image/etc-hosts} ${
                pkgs.writeText "expected-full" thinkpadEtcHostsText
              } >&2 || true
              exit 1
            '';
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

      # ── Thinkpad hosts codegen ─────────────────────────────────────
      # Regenerate hosts/thinkpad/host-image/nebula-hosts from
      # lib/host-meta.nix. Run from a repo checkout (it writes into the
      # working tree — a flake fetched from a registry is read-only), then
      # commit the result; `nix flake check` enforces freshness.
      # NOTE: the target is a RELATIVE path (the app runs in the caller's
      # cwd, and `nix run .#…` implies the cwd is the repo root);
      # self.outPath can't be used — in a dirty tree it's the read-only
      # store copy.
      apps.x86_64-linux.render-thinkpad-hosts = {
        type = "app";
        program = "${
            pkgs.writeShellScriptBin "render-thinkpad-hosts" ''
              set -euo pipefail
              target="hosts/thinkpad/host-image/nebula-hosts"
              target_full="hosts/thinkpad/host-image/etc-hosts"
              if [ ! -f flake.nix ] || [ ! -f lib/host-meta.nix ]; then
                echo "ERROR: run from the cn repo root (this writes into the working tree)." >&2
                exit 1
              fi
              cp -f ${pkgs.writeText "nebula-hosts" thinkpadHostsText} "$target"
              cp -f ${
                pkgs.writeText "etc-hosts" thinkpadEtcHostsText
              } "$target_full"
              chmod 644 "$target" "$target_full"
              echo "rendered ''${target} + ''${target_full}:"
              cat "$target_full"
            ''
          }/bin/render-thinkpad-hosts";
      };
    };
}
