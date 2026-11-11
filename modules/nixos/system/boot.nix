{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.system.boot;
in
{
  options.my.system.boot = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant != "minimal" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    # Bootloader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.supportedFilesystems = [ "ntfs" ];
  };
}
