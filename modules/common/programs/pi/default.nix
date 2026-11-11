# The Pi coding agent and the local extensions in ./extensions; the Home Manager side is ./home.nix.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.programs.pi;
in
{
  options.my.programs.pi = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      imports = [ ./home.nix ];
    };
  };
}
