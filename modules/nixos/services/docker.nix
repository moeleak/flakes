{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.docker;
in
{
  options.my.services.docker = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant != "minimal" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    users.users.${config.my.user}.extraGroups = [
      "docker"
    ];
    virtualisation = {
      docker = {
        enable = true;
        rootless.enable = true;
      };
    };
  };
}
