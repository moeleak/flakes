# The main user's Home Manager environment. Modules add their user-level
# settings to `home-manager.users.${config.my.user}` next to their system ones.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home;
in
{
  options.my.home = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = { };
  };

  config = lib.mkIf (cfg != null) {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;

      users.${config.my.user} = {
        home.stateVersion = "25.11";
      };
      extraSpecialArgs = {
        inherit inputs pkgs;
      };
    };
  };
}
