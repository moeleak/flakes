{ config, ... }:

{
  sops = {
    secrets."frp-token".sopsFile = ../../../secrets/frp.yaml;
    secrets."frp-user".sopsFile = ../../../secrets/frp.yaml;
    templates."frp.env" = {
      content = ''
        FRP_TOKEN=${config.sops.placeholder."frp-token"}
        FRP_USER=${config.sops.placeholder."frp-user"}
      '';
      restartUnits = [ "frp.service" ];
    };
  };

  services.frp = {
    instances."" = {
      enable = true;
      role = "client";
      environmentFiles = [
        config.sops.templates."frp.env".path
      ];
      settings = {
        serverAddr = "47.107.83.180";
        serverPort = 7000;

        auth = {
          method = "token";
          token = "{{ .Envs.FRP_TOKEN }}";
        };
        user = "{{ .Envs.FRP_USER }}";

        proxies = [
          {
            name = "proxy_20260730152817_1487ea8d"; # Velocity
            type = "tcp";
            localPort = 25500;
            remotePort = 25500;
          }
          {
            name = "proxy_20260730152749_959bdd81"; # Simple Voice Chat
            type = "udp";
            localPort = 11110;
            remotePort = 11110;
          }
          {
            name = "proxy_20260730152850_e569d851"; # Geyser
            type = "udp";
            localPort = 19132;
            remotePort = 19132;
          }
          {
            name = "proxy_20260730152913_e84571c6"; # 模组服
            type = "tcp";
            localPort = 25502;
            remotePort = 25502;
          }
        ];
      };
    };
  };
}
