{
  lib,
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ../../../environment-variables.nix
    ../../../system/nix.nix
    ../../../programs/shell.nix
    ../../../programs/sing-box.nix
    ../../../programs/tmux.nix
  ];

  users.users.lolimaster = {
    home = "/Users/lolimaster";
    shell = pkgs.fish;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.lolimaster = import ../../../home-manager/home.nix;
    extraSpecialArgs = {
      inherit inputs pkgs;
      stdenv.hostPlatform.system = "aarch64-darwin";
    };

  };

  system.stateVersion = 6;
}
