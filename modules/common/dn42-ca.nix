# DN42's root certificate (pkgs/dn42-ca.nix), trusted by the system; its Name
# Constraints let it vouch only for .dn42, 172.20.0.0/14 and fd42::/16.
#
# NixOS and nix-darwin add it to /etc/ssl/certs/ca-certificates.crt, which
# OpenSSL, curl, git, Go and Nix read. macOS's own programs (Safari, Chrome,
# whatever uses its TLS) trust the System keychain instead, where activation
# adds it as a root once: macOS asks for an administrator's password for that,
# so a switch without a GUI session (over SSH) only warns, and the next one
# tries again. Zen gets it through its own policy
# (programs/zen-browser.nix), as Firefox reads neither.
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.my.system.dn42-ca;
  isDarwin = options ? launchd;
  ca = pkgs.callPackage ../../pkgs/dn42-ca.nix { };
in
{
  options.my.system.dn42-ca = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = { };
  };

  config = lib.mkIf (cfg != null) (
    lib.mkMerge [
      { security.pki.certificateFiles = [ ca ]; }

      (lib.optionalAttrs isDarwin {
        system.activationScripts.postActivation.text = ''
          if ! /usr/bin/security dump-trust-settings -d 2>/dev/null | /usr/bin/grep -q 'dn42 Root Authority CA'; then
            echo "adding DN42's root certificate to the System keychain..." >&2
            /usr/bin/security add-trusted-cert -d -r trustRoot \
              -k /Library/Keychains/System.keychain ${ca} ||
              echo "warning: DN42's root certificate is not in the System keychain yet (macOS asks for a password in a GUI session); the next switch tries again" >&2
          fi
        '';
      })
    ]
  );
}
