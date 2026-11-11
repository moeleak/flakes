# Host-specific key bindings are set by the hosts (see their keyd.nix).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.kitty;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  options.my.programs.kitty = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null && config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      programs.kitty = {
        enable = true;
        font.name = "Maple Mono NF CN";
        font.size = if isLinux then 14 else 18;
        font.package = pkgs.maple-mono.NF-CN;
        settings.macos_option_as_alt = true;
        themeFile = "Nord";
      };
    };
  };
}
