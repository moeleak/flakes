{
  config,
  lib,
  pkgs,
  options,
  ...
}:

let
  singBoxSettings = config.programs.sing-box.settings;

  userHome =
    if config.users.users ? lolimaster then
      config.users.users.lolimaster.home
    else if config.users.users ? moeleak then
      config.users.users.moeleak.home
    else
      null;
in
{
  imports = [ ./sing-box-config.nix ];

  config = lib.mkMerge [
    {
      programs.sing-box.mode =
        if config.networking.hostName == "LoliIsland-PC-Nix" then "http" else "tun";

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

    (lib.optionalAttrs
      (options ? networking && options.networking ? proxy)
      {
        networking.proxy = lib.mkIf
          (config.networking.hostName == "LoliIsland-PC-Nix")
          {
            httpProxy = "http://127.0.0.1:1080/";
            httpsProxy = "http://127.0.0.1:1080/";
          };
      })

    # Linux
    (lib.optionalAttrs (options.services ? sing-box) {
      services.sing-box = {
        enable = true;
        settings = singBoxSettings;
      };
    })

    # macOS
    (lib.optionalAttrs (options ? launchd) {
      networking.knownNetworkServices = [
        "Wi-Fi"
      ];
      networking.dns = [ "127.0.0.1" ];
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
          StandardErrorPath = "/var/log/sing-box.log";
        };
      };
    })
  ];
}
