# frp client. The token and user come from the `frp-token` and `frp-user`
# secrets; a host only lists the server and what it exposes.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.frp;
in
{
  options.my.services.frp = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          serverAddr = lib.mkOption { type = lib.types.str; };
          serverPort = lib.mkOption {
            type = lib.types.port;
            default = 7000;
          };
          # frp proxy definitions: name, type, localPort, remotePort, ...
          proxies = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            default = [ ];
          };
        };
      }
    );
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    sops = {
      secrets."frp-token" = { };
      secrets."frp-user" = { };
      templates."frp-primary.env" = {
        content = ''
          FRP_TOKEN=${config.sops.placeholder."frp-token"}
          FRP_USER=${config.sops.placeholder."frp-user"}
        '';
        restartUnits = [ "frp-primary.service" ];
      };
    };

    services.frp.instances.primary = {
      enable = true;
      role = "client";
      environmentFiles = [ config.sops.templates."frp-primary.env".path ];
      settings = {
        inherit (cfg) serverAddr serverPort proxies;
        auth = {
          method = "token";
          token = "{{ .Envs.FRP_TOKEN }}";
        };
        user = "{{ .Envs.FRP_USER }}";
      };
    };
  };
}
