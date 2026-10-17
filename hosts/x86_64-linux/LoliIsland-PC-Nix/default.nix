{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./keyd.nix
    ./strata.nix
    ../../../system/boot.nix
    ../../../system/pcscd.nix
    ../../../system/sops.nix
    ../../../desktop/plasma.nix
    ../../../system/samba.nix
    ../../../programs/sing-box
    ../../../programs/sunshine.nix
    ../../../programs/ollama.nix
    ../../../programs/openssh.nix
    ../../../programs/gnupg.nix
    ../../../programs/rime.nix
    ../../../programs/shell.nix
    ../../../programs/steam.nix
    ../../../programs/tmux.nix
    ../../../programs/xkb.nix
    ../../../programs/llama.nix
    ../../../zone/fonts.nix
    ../../../zone/locale.nix
    ../../../hardware/NV.nix
    ../../../hardware/NVFanControl.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  zramSwap = {
    enable = true;
    algorithm = "zstd"; # Compression algorithm (e.g., zstd, lz4)
    memoryPercent = 100; # Percentage of total RAM to use for zram
    priority = 10; # Swap priority (set higher than regular swap/swapfile)
  };

  networking.hostName = "LoliIsland-PC-Nix"; # Define your hostname.

  users.users.moeleak = {
    shell = pkgs.fish;
    isNormalUser = true;
    description = "moeleak";
    home = "/home/moeleak";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # make home-manager as a module of nixos
  # so that home-manager configuration will be deployed automatically when executing `nixos-rebuild switch`
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.moeleak = import ../../../home-manager/home.nix;
    extraSpecialArgs = {
      inherit inputs pkgs;
      stdenv.hostPlatform.system = "x86_64-linux";
    };

  };

  programs.nix-ld.enable = true;

  system.stateVersion = "25.05"; # Did you read the comment?
}
