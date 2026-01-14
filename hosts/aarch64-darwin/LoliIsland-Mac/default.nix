{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ../../../system/nix.nix
    ../../../system/sops.nix
    ../../../programs/shell.nix
    ../../../programs/sing-box.nix
    ../../../programs/tmux.nix
  ];

  networking.hostName = "LoliIsland-Mac";

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
