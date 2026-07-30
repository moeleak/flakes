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
    instances."frp" = {
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
            name = "minecraft-velocity-1.21.11";
            type = "tcp";
            localPort = 25500;
            remotePort = 25500;
          }
          {
            name = "minecraft-fabric-1.21.11 simple voice chat";
            type = "udp";
            localPort = 11110;
            remotePort = 11110;
          }
          {
            name = "minecraft-geyser-1.21.11";
            type = "udp";
            localPort = 19132;
            remotePort = 19132;
          }
          {
            name = "minecraft-mods";
            type = "tcp";
            localPort = 25502;
            remotePort = 25502;
          }
        ];
      };
    };
  };
}
