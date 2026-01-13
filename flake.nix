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

    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs-latest";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs-latest";
    };

    mango = {
      url = "github:DreamMaoMao/mango";
      inputs.nixpkgs.follows = "nixpkgs-latest";
    };

    disko.url = "github:nix-community/disko";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    
    llm-agents.url = "github:numtide/llm-agents.nix";
    opencode.url = "github:sst/opencode/dev";

    nixvim.url = "github:nix-community/nixvim/nixos-25.11";
    nixvim.inputs.nixpkgs.follows = "nixpkgs-latest";
  };

  outputs = { self, nixpkgs, nixpkgs-latest, nixpkgs-unstable, home-manager, dms, niri, mango, disko, nixos-anywhere, llm-agents, opencode, nixvim }: {
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
      specialArgs = { inherit disko opencode nixpkgs-unstable dms niri mango; };
      modules = [
        { nixpkgs.config.allowUnfree = true; }
        ./modules/unstable-packages.nix
        ./bee/configuration.nix
        ./bee/disk-config.nix
        disko.nixosModules.disko
      ];
    };

    # think configuration - ThinkPad T14
    nixosConfigurations.think = nixpkgs-latest.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit disko opencode dms niri mango nixpkgs-unstable; };
      modules = [
        { nixpkgs.config.allowUnfree = true; }
        ./modules/unstable-packages.nix
        ./think/configuration.nix
        ./think/disk-config.nix
        disko.nixosModules.disko
      ];
    };

    homeConfigurations.bee = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs-latest.legacyPackages.x86_64-linux;
      modules = [
        { nixpkgs.config.allowUnfree = true; }
        niri.homeModules.niri
        nixvim.homeModules.nixvim
        ./bee/home.nix
      ];
      extraSpecialArgs = { inherit opencode llm-agents dms niri nixvim; };
    };

    homeConfigurations.think = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs-latest.legacyPackages.x86_64-linux;
      modules = [
        { nixpkgs.config.allowUnfree = true; }
        niri.homeModules.niri
        nixvim.homeModules.nixvim
        ./think/home.nix
      ];
      extraSpecialArgs = { inherit opencode llm-agents dms niri nixvim; };
    };
  };
}

