{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.zen-browser;
in
{
  options.my.programs.zen-browser = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null && config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      imports = [ inputs.zen-browser.homeModules.beta ];

      programs.zen-browser.enable = true;

      programs.zen-browser.profiles.main.settings = {
        "browser.ctrlTab.sortByRecentlyUsed" = true;
        "browser.translations.neverTranslateLanguages" = "zh-Hans";
      };

      programs.zen-browser.globalExtensions =
        with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
          ublock-origin
          vimium
        ];
    };
  };
}
