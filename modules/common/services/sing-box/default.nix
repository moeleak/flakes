{
  config,
  lib,
  pkgs,
  options,
  ...
}:

let
  cfg = config.my.services.sing-box;
  isLabServer = cfg.lab == "server";
  isLabClient = cfg.lab == "client";

  singBoxSettings = import ./config.nix {
    inherit
      config
      lib
      pkgs
      isLabServer
      isLabClient
      ;
  };
in
{
  options.my.services.sing-box = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        # server: accept the Lab relay; client: send traffic through it.
        options.lab = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "server"
              "client"
            ]
          );
          default = null;
        };
      }
    );
    default = { };
  };

  config = lib.mkIf (cfg != null) (lib.mkMerge [
    {
      environment.systemPackages = [ pkgs.sing-box ];

      sops.secrets = lib.genAttrs (
        [
          "sing-box-hysteria-lax-server"
          "sing-box-hysteria-lax-password"
          "sing-box-hysteria-lax-pin"
          "sing-box-hysteria-as3-server"
          "sing-box-hysteria-as3-password"
          "sing-box-hysteria-as3-pin"
        ]
        ++ lib.optional (cfg.lab != null) "sing-box-lab-password"
      ) (_: { });
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
  ]);
}
