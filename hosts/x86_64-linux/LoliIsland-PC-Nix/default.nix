{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./keyd.nix
    ./strata.nix
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  my = {
    variant = "desktop";
    desktop.plasma = { };
    hardware.nvidia.fanControl = true;
    programs.llama = { };
    programs.obs = { };
    services = {
      ollama = { };
      samba = { };
      sing-box.lab = "client";
      sunshine = { };
      winboat = { };
    };
  };

  fileSystems."/".options = [ "compress-force=zstd" ];

  # Secure Boot
  environment.systemPackages = [ pkgs.sbctl ];
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd"; # Compression algorithm (e.g., zstd, lz4)
    memoryPercent = 100; # Percentage of total RAM to use for zram
    priority = 10; # Swap priority (set higher than regular swap/swapfile)
  };

  system.stateVersion = "25.05"; # Did you read the comment?
}
