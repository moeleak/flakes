{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./keyd.nix
    ../../../system/boot.nix
    ../../../desktop.nix
    ../../../environment-variables.nix
    ../../../programs/mihomo.nix
    ../../../programs/ollama.nix
    ../../../programs/openssh.nix
    ../../../programs/rime.nix
    ../../../programs/shell.nix
    ../../../programs/steam.nix
    ../../../programs/tailscale.nix
    ../../../programs/tmux.nix
    ../../../programs/xkb.nix
    ../../../programs/llama.nix
    ../../../zone/fonts.nix
    ../../../zone/locale.nix
    ../../../hardware/NV.nix
    ../../../hardware/NVFanControl.nix
  ];

  networking.hostName = "LoliIsland-PC-Nix"; # Define your hostname.

  users.users.moeleak = {
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
      pkgs-5a07111 = (
        import inputs.nixpkgs-5a07111 {
          stdenv.hostPlatform.system = "x86_64-linux";
          config.allowUnfree = true;
          config.cudaSupport = true;
        }
      );
    };

  };

  programs.nix-ld.enable = true;

  system.stateVersion = "25.05"; # Did you read the comment?
}
