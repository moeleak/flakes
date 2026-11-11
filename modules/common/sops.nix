# Secrets. A module declares what it needs with `sops.secrets."name" = { };`
# and the file under secrets/ that contains that key is found automatically.
#
# Hosts decrypt with the main user's SSH key, or with the YubiKey when
# `my.sops.yubikey` is set (identity exported to keys.txt once, see README).
# Home Manager follows the same choice through osConfig.
{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  cfg = config.my.sops;
  home = config.users.users.${config.my.user}.home;
  plugin = pkgs.age-plugin-yubikey;
  isDarwin = options ? launchd;

  secretsDir = ../../secrets;
  secretFiles = builtins.filter (lib.hasSuffix ".yaml") (
    builtins.attrNames (builtins.readDir secretsDir)
  );
  # Top-level keys of a sops file; nested lines are indented and do not match.
  keysIn =
    file:
    lib.concatMap (
      line:
      let
        key = builtins.match "([^[:space:]#:]+):.*" line;
      in
      lib.optionals (key != null) key
    ) (lib.splitString "\n" (builtins.readFile (secretsDir + "/${file}")));
  fileOf =
    key:
    let
      found = builtins.filter (file: builtins.elem key (keysIn file)) secretFiles;
    in
    if found == [ ] then
      throw "sops: no file in secrets/ contains the key '${key}'"
    else
      secretsDir + "/${builtins.head found}";
in
{
  options.my.sops.yubikey = lib.mkOption {
    type = lib.types.bool;
    default = false;
  };

  options.sops.secrets = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          config.sopsFile = lib.mkDefault (fileOf config.key);
        }
      )
    );
  };

  config = lib.mkMerge [
    {
      sops = {
        gnupg.sshKeyPaths = [ ];
        age.sshKeyPaths = lib.optional (!cfg.yubikey) "${home}/.ssh/id_ed25519";
      };
    }

    (lib.mkIf cfg.yubikey {
      environment.systemPackages = [ plugin ];
      sops.age = {
        keyFile = "${home}/.config/sops/age/keys.txt";
        plugins = [ plugin ];
      };
    })

    (lib.optionalAttrs isDarwin {
      sops.environment.PATH = lib.mkIf cfg.yubikey (
        lib.mkForce "/usr/bin:/bin:/usr/sbin:/sbin:${lib.makeBinPath [ plugin ]}"
      );
      # Retry on failure so secrets are decrypted after YubiKey is inserted.
      launchd.daemons.sops-install-secrets.serviceConfig = lib.mkIf cfg.yubikey {
        KeepAlive = lib.mkForce { SuccessfulExit = false; };
        ThrottleInterval = 5;
      };
    })

    (lib.optionalAttrs (!isDarwin) {
      # Secrets are installed during activation, before pcscd.service is up.
      system.activationScripts = lib.mkIf cfg.yubikey {
        setupYubikeyForSopsNix.text = ''
          PATH=$PATH:${lib.makeBinPath [ plugin ]}
          ${pkgs.runtimeShell} -c "mkdir -p /var/lib/pcsc && ln -sfn ${pkgs.ccid}/pcsc/drivers /var/lib/pcsc/drivers"
          ${pkgs.toybox}/bin/pgrep pcscd > /dev/null && ${pkgs.toybox}/bin/pkill pcscd
          ${pkgs.pcsclite}/bin/pcscd
        '';
        setupSecrets.deps = [ "setupYubikeyForSopsNix" ];
      };
    })
  ];
}
