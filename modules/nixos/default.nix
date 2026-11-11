{ inputs, ... }:
{
  imports = [
    ../common
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.default
  ]
  ++ import ../../lib/find-modules.nix ./.;
}
