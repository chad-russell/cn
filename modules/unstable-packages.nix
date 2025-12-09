{ pkgs, nixpkgs-unstable, ... }:

{
  # This module makes pkgsUnstable available via options
  # Other modules can access it via config._module.args.pkgsUnstable
  _module.args.pkgsUnstable = nixpkgs-unstable.legacyPackages.${pkgs.system};
}


