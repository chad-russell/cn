{
  description = "NixOS configuration for k3";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }:
    {
      nixosConfigurations.k3 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./disk-config.nix
          ./configuration.nix
          ./hardware-configuration.nix
        ];
      };
    };
}
