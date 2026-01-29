{ config
, lib
, options
, pkgs
, ...
}:

let
  userHome =
    if config.users.users ? lolimaster then
      config.users.users.lolimaster.home
    else if config.users.users ? moeleak then
      config.users.users.moeleak.home
    else
      null;
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = [ pkgs.age-plugin-yubikey ];
      sops = {
        defaultSopsFile = ../secrets/sing-box.yaml;
        environment.PATH = lib.mkForce "/usr/bin:/bin:/usr/sbin:/sbin:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]}";
        gnupg.sshKeyPaths = [ ];
        age.sshKeyPaths = [ ];
        # age.sshKeyPaths = [ "${userHome}/.ssh/id_ed25519" ];
        age.keyFile = "${userHome}/.config/sops/age/keys.txt";
        age.plugins = [ pkgs.age-plugin-yubikey ];
        secrets = {
          "sing-box-guanran-uuid" = { };
          "sing-box-guanran-lax0-server" = { };
          "sing-box-guanran-tyo0-server" = { };
          "sing-box-moeleak-lax-server" = { };
          "sing-box-moeleak-lax-uuid" = { };
          "sing-box-moeleak-lax-public-key" = { };
          "sing-box-moeleak-lax-short-id" = { };
        };
      };
    }
    (lib.mkIf pkgs.stdenv.isLinux {
      system.activationScripts = {
        setupYubikeyForSopsNix.text = ''
          PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ] }
          ${pkgs.runtimeShell} -c "mkdir -p /var/lib/pcsc && ln -sfn ${pkgs.ccid}/pcsc/drivers /var/lib/pcsc/drivers"
          ${pkgs.toybox}/bin/pgrep pcscd > /dev/null && ${pkgs.toybox}/bin/pkill pcscd
          ${pkgs.pcsclite}/bin/pcscd
        '';
        setupSecrets.deps = [ "setupYubikeyForSopsNix" ];
      };
    })
    (lib.optionalAttrs (options ? launchd) {
      launchd.daemons.sops-install-secrets.serviceConfig = {
        # Retry on failure so secrets are decrypted after YubiKey is inserted.
        KeepAlive = lib.mkForce {
          SuccessfulExit = false;
        };
        ThrottleInterval = 5;
      };
    })
  ];
}
