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
    ../../../programs/ollama.nix
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
      vaapiIntel
      vaapiVdpau
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
      inherit inputs;
      system = "x86_64-linux";
      pkgs-5a07111 = (
        import inputs.nixpkgs-5a07111 {
          system = "x86_64-linux";
          config.allowUnfree = true;
        }
      );
    };

  };
}
