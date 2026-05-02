{
  description = "NixOS configuration with niri and Noctalia shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-shell = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vicinae.url = "github:vicinaehq/vicinae";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
      home-manager,
      noctalia-shell,
      vicinae,
      nixos-hardware,
      nixvim,
      agenix,
      zen-browser,
      ...
    }:
    let
      system = "x86_64-linux";
      hostName = "think";
      username = "crussell";

      # Custom local packages
      overlay = final: prev: {
        slk = final.callPackage ./pkgs/slk/package.nix { };
      };
    in
    {
      nixosConfigurations.${hostName} = nixpkgs.lib.nixosSystem {
        inherit system;

        modules = [
          { nixpkgs.overlays = [ overlay ]; }

          ./hardware-configuration.nix
          ./configuration.nix

          # ThinkPad T14 Gen 6 Intel (Lunar Lake) hardware profile
          nixos-hardware.nixosModules.lenovo-thinkpad-t14-intel-gen6

          # Make 'username' available as a module argument
          { _module.args.username = username; }

          # Niri is now in nixpkgs — enable it in configuration.nix with:
          #   programs.niri.enable = true;

          # Noctalia shell NixOS module — provides services.noctalia-shell
          noctalia-shell.nixosModules.default

          # Home Manager
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
            home-manager.users.${username} = import ./home.nix;

            # Pass flake inputs to home-manager modules
            home-manager.extraSpecialArgs = {
              inherit noctalia-shell;
              inherit vicinae;
              inherit agenix;
            };

          }
        ];
      };
    };
}
