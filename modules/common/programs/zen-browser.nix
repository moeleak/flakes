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

      # DN42's sites have certificates from its own authority, whose root
      # (../dn42-ca.nix) Zen trusts on its own, as it reads neither the
      # system's roots nor the Mac's keychain. On macOS the policies go
      # through the app's defaults.
      programs.zen-browser.policies.Certificates.Install = lib.optional (
        config.my.system.dn42-ca != null
      ) "${config.my.system.dn42-ca.file}";

      programs.zen-browser.globalExtensions =
        with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
          ublock-origin
          vimium
        ];
    };
  };
}
