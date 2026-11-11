{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.system.network;
in
{
  options.my.system.network = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant != "minimal" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    # Enable networking
    networking.networkmanager.enable = true;

    # Or disable the firewall altogether.
    networking.firewall.enable = false;
  };
}
