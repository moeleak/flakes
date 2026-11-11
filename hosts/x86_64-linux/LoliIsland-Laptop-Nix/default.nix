{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./audio.nix
    ./keyd.nix
  ];

  my = {
    variant = "desktop";
    desktop.sway = { };
    sops.yubikey = true;
  };

  boot = {
    initrd.verbose = false;
    kernelParams = lib.mkAfter [
      "nosgx"
    ];
  };

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

  system.stateVersion = "25.05";
}
