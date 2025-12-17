{
  config,
  lib,
  pkgs,
  options,
  ...
}:

let
  singBoxSettings = import ./sing-box-config.nix { inherit config; };

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
      environment.systemPackages = [ pkgs.sing-box ];

      sops = lib.mkIf (userHome != null) {
        defaultSopsFile = ../secrets/sing-box.yaml;
        gnupg.sshKeyPaths = [ ];
        age.sshKeyPaths = [ "${userHome}/.ssh/id_ed25519" ];
        secrets = {
          "sing-box-vless-uuid" = { };
          "sing-box-lax0-server" = { };
          "sing-box-tyo0-server" = { };
          "sing-box-tyo1-server" = { };
        };
      };
    }

    # Linux
    (lib.optionalAttrs (options.services ? sing-box) {
      services.sing-box = {
        enable = true;
        settings = singBoxSettings;
      };
    })

    # macOS
    (lib.optionalAttrs (options ? launchd) {
      launchd.daemons.sing-box = {
        script =
          let
            utils = import "${pkgs.path}/nixos/lib/utils.nix" { inherit lib config pkgs; };
          in
          ''
            mkdir -m 700 -p /var/lib/sing-box
            ${utils.genJqSecretsReplacementSnippet singBoxSettings "/var/lib/sing-box/config.json"}
            exec ${pkgs.sing-box}/bin/sing-box -D /var/lib/sing-box run -c /var/lib/sing-box/config.json
          '';
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "/var/log/sing-box.out.log";
          StandardErrorPath = "/var/log/sing-box.err.log";
        };
      };
    })
  ];
}
