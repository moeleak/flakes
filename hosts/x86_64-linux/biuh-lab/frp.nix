{ config, ... }:

{
  sops = {
    secrets."frp-ngb-moeleak-token".sopsFile = ../../../secrets/frp.yaml;
    templates."frp-ngb-moeleak.env" = {
      content = ''
        FRP_TOKEN=${config.sops.placeholder."frp-ngb-moeleak-token"}
      '';
      restartUnits = [ "frp-ngb-moeleak.service" ];
    };
  };

  services.frp = {
    instances."ngb-moeleak" = {
      enable = true;
      role = "client";
      environmentFiles = [
        config.sops.templates."frp-ngb-moeleak.env".path
      ];
      settings = {
        serverAddr = "114.66.6.101";
        serverPort = 7111;
        transport.protocol = "quic";

        auth = {
          method = "token";
          token = "{{ .Envs.FRP_TOKEN }}";
        };

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
          {
            name = "jupyter";
            type = "tcp";
            localPort = 8888;
            remotePort = 8888;
          }
        ];
      };
    };
  };
}
