{
  description = "NixOS configurations for homelab cluster";

  nixConfig = {
    extra-substituters = [
      "https://numtide.cachix.org"
    ];
    extra-trusted-public-keys = [
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-latest.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Home Manager (use master for latest nixpkgs compatibility)
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-latest";

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
  };
}

