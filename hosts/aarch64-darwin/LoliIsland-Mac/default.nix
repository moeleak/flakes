{ pkgs, ... }:
{
  my = {
    variant = "desktop";
    user = "lolimaster";
    sops.yubikey = true;
    services.sing-box.lab = "client";
  };

  users.users.lolimaster = {
    home = "/Users/lolimaster";
    shell = pkgs.fish;
  };

  system.stateVersion = 6;
}
