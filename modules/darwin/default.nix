{ inputs, ... }:
{
  imports = [
    ../common
    inputs.sops-nix.darwinModules.sops
    inputs.home-manager.darwinModules.default
  ];
}
