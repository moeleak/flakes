{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  hostName = config.networking.hostName or "";
  sshKeyHosts = [
    "LoliIsland-PC-Nix"
    "lp4a"
  ];
  useSshKey = builtins.elem hostName sshKeyHosts;
  useKeyFile = userHome != null && !useSshKey;
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
      sops = {
        gnupg.sshKeyPaths = [ ];
        age.sshKeyPaths = lib.mkForce (
          lib.optionals (useSshKey && userHome != null) [ "${userHome}/.ssh/id_ed25519" ]
        );
        secrets = {
          "sing-box-guanran-uuid" = {
            sopsFile = ../secrets/sing-box.yaml;
          };
          "sing-box-guanran-lax0-server" = {
            sopsFile = ../secrets/sing-box.yaml;
          };
          "sing-box-guanran-tyo0-server" = {
            sopsFile = ../secrets/sing-box.yaml;
          };
          "sing-box-moeleak-lax-server" = {
            sopsFile = ../secrets/sing-box.yaml;
          };
          "sing-box-moeleak-lax-uuid" = {
            sopsFile = ../secrets/sing-box.yaml;
          };
          "sing-box-moeleak-lax-public-key" = {
            sopsFile = ../secrets/sing-box.yaml;
          };
          "sing-box-moeleak-lax-short-id" = {
            sopsFile = ../secrets/sing-box.yaml;
          };
        };
      };
    }
    (lib.mkIf useKeyFile {
      environment.systemPackages = [ pkgs.age-plugin-yubikey ];
      sops = {
        environment.PATH = lib.mkForce "/usr/bin:/bin:/usr/sbin:/sbin:${
          lib.makeBinPath [ pkgs.age-plugin-yubikey ]
        }";
        age.keyFile = "${userHome}/.config/sops/age/keys.txt";
        age.plugins = [ pkgs.age-plugin-yubikey ];
      };
    })
    (lib.mkIf (pkgs.stdenv.isLinux && useKeyFile) {
      system.activationScripts = {
        setupYubikeyForSopsNix.text = ''
          PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]}
          ${pkgs.runtimeShell} -c "mkdir -p /var/lib/pcsc && ln -sfn ${pkgs.ccid}/pcsc/drivers /var/lib/pcsc/drivers"
          ${pkgs.toybox}/bin/pgrep pcscd > /dev/null && ${pkgs.toybox}/bin/pkill pcscd
          ${pkgs.pcsclite}/bin/pcscd
        '';
        setupSecrets.deps = [ "setupYubikeyForSopsNix" ];
      };
    })
    (lib.optionalAttrs (options ? launchd) {
      launchd.daemons.sops-install-secrets.serviceConfig = lib.mkIf useKeyFile {
        # Retry on failure so secrets are decrypted after YubiKey is inserted.
        KeepAlive = lib.mkForce {
          SuccessfulExit = false;
        };
        ThrottleInterval = 5;
      };
    })
  ];
}
