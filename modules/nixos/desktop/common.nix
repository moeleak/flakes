# What every desktop machine has, whichever desktop it runs.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf (config.my.variant == "desktop") {
    users.users.${config.my.user} = {
      shell = pkgs.fish;
      isNormalUser = true;
      description = config.my.user;
      home = "/home/${config.my.user}";
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
    };

    boot.kernelPackages = pkgs.linuxPackages_latest;

    programs.nix-ld.enable = true;
  };
}
