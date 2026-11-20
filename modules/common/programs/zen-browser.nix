{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.zen-browser;

  # DN42's root certificate alone. nixpkgs' file starts with `openssl x509
  # -text` output, which the certificate policy cannot parse: it only strips
  # what precedes the PEM header on the header's own line.
  dn42Ca = pkgs.runCommandLocal "dn42-ca.pem" { } ''
    sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
      ${pkgs.dn42-cacert}/etc/ssl/certs/dn42-ca.crt > $out
  '';
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

      # DN42's sites have certificates from its own authority, whose root may
      # only vouch for .dn42, 172.20.0.0/14 and fd42::/16. On macOS the
      # policies go through the app's defaults.
      programs.zen-browser.policies.Certificates.Install = [ "${dn42Ca}" ];

      programs.zen-browser.globalExtensions =
        with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
          ublock-origin
          vimium
        ];
    };
  };
}
