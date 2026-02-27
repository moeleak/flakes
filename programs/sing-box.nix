{
  config,
  lib,
  pkgs,
  options,
  ...
}:

let
  singBoxSettings = import ./sing-box-config.nix { inherit config; };
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = [ pkgs.sing-box ];
    }

    # Linux
    (lib.optionalAttrs (options.services ? sing-box) {
      networking.nameservers = [ "127.0.0.1 " ];
      networking.search = [ "tailf5f129.ts.net" ];
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
      networking.search = [ "tailf5f129.ts.net" ];
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
