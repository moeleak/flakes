{
  lib,
  inputs,
  pkgs,
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
    ../../../programs/openssh.nix
    ../../../programs/rime.nix
    ../../../programs/shell.nix
    ../../../programs/steam.nix
    ../../../programs/tailscale.nix
    ../../../programs/tmux.nix
    ../../../programs/xkb.nix
    ../../../zone/fonts.nix
    ../../../zone/locale.nix
  ];

  networking.hostName = "LoliIsland-Laptop-Nix"; # Define your hostname.

  users.users.moeleak = {
    isNormalUser = true;
    description = "moeleak";
    home = "/home/moeleak";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "snd_hda_intel" ];
  boot.extraModprobeConfig = ''
    options snd-intel-dspcfg dsp_driver=1
    options snd-hda-intel model=auto
    options snd-hda-intel dmic_detect=0
  '';
  hardware.firmware = [
    pkgs.sof-firmware
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
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
        }
      );
    };

  };

  programs.nix-ld.enable = true;
  system.stateVersion = "25.05";
}
