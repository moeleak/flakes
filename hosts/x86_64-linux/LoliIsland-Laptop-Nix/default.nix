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

  boot.kernelParams = lib.mkAfter [
    "nosgx"
    # A quiet stage 1: systemd's status only on errors and delays.
    "rd.systemd.show_status=auto"
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

  system.stateVersion = "25.05";
}
