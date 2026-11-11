# Claude Code provider switching; the Home Manager side is ./home.nix.
{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.my.programs.claude;
in
{
  options.my.programs.claude = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      imports = [
        inputs.sops-nix.homeManagerModules.sops
        ./home.nix
      ];
    };
  };
}
