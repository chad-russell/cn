{
  description = "NixOS configurations for homelab cluster";

  nixConfig = {
    extra-substituters = [
      "https://numtide.cachix.org"
      "https://niri.cachix.org"
    ];
    extra-trusted-public-keys = [
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-latest.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Home Manager (use master for latest nixpkgs compatibility)
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-latest";

    # Dank Material Shell
    dgop = {
      url = "github:AvengeMedia/dgop";
      inputs.nixpkgs.follows = "nixpkgs-latest";
    };

    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs-latest";
      inputs.dgop.follows = "dgop";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs-latest";
    };

    # Vicinae - workspace switcher
    vicinae.url = "github:vicinaehq/vicinae";

    disko.url = "github:nix-community/disko";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    
    llm-agents.url = "github:numtide/llm-agents.nix";
    opencode.url = "github:sst/opencode/dev";
  };

  outputs = { self, nixpkgs, nixpkgs-latest, nixpkgs-unstable, home-manager, dgop, dms, niri, vicinae, disko, nixos-anywhere, llm-agents, opencode }: {
    # k2 configuration
    nixosConfigurations.k2 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit disko; };
      modules = [
        ./k2/configuration.nix
        ./k2/disk-config.nix
        ./common/hardware-configuration.nix
        disko.nixosModules.disko
      ];
    };

    # k3 configuration
    nixosConfigurations.k3 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit disko; };
      modules = [
        ./k3/configuration.nix
        ./k3/disk-config.nix
        ./common/hardware-configuration.nix
        disko.nixosModules.disko
      ];
    };

    # k4 configuration
    nixosConfigurations.k4 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit disko; };
      modules = [
        ./k4/configuration.nix
        ./k4/disk-config.nix
        ./common/hardware-configuration.nix
        disko.nixosModules.disko
      ];
    };

    # bee configuration - Beelink SER7
    nixosConfigurations.bee = nixpkgs-latest.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit disko opencode nixpkgs-unstable dms; };
      modules = [
        { nixpkgs.config.allowUnfree = true; }
        ./modules/unstable-packages.nix
        ./bee/configuration.nix
        ./bee/disk-config.nix
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.crussell = ./bee/home.nix;
          home-manager.extraSpecialArgs = { inherit vicinae opencode; };
        }
      ];
    };

    # think configuration - ThinkPad T14
    nixosConfigurations.think = nixpkgs-latest.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit disko opencode dms niri nixpkgs-unstable; };
      modules = [
        { nixpkgs.config.allowUnfree = true; }
        ./modules/unstable-packages.nix
        ./think/configuration.nix
        ./think/disk-config.nix
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.crussell = ./think/home.nix;
          home-manager.extraSpecialArgs = { inherit vicinae opencode llm-agents dms niri; };
        }
      ];
    };
  };
}

