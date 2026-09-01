{ config, pkgs, ... }:

let
  chmlfrpFrpc = pkgs.callPackage ../../../pkgs/chmlfrp-frpc.nix { };
  chmlfrpStart = pkgs.writeShellScript "frp-chml-start" ''
    set -eu

    apiToken="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/api-token")"
    exec ${chmlfrpFrpc}/bin/frpc \
      --token "$apiToken" \
      --id 339296 \
      --config "$RUNTIME_DIRECTORY/frpc.ini"
  '';
in

{
  sops = {
    secrets."frp-token".sopsFile = ../../../secrets/frp.yaml;
    secrets."frp-user".sopsFile = ../../../secrets/frp.yaml;
    secrets."frp-chml-user" = {
      sopsFile = ../../../secrets/frp.yaml;
      restartUnits = [ "frp-chml.service" ];
    };
    templates."frp-primary.env" = {
      content = ''
        FRP_TOKEN=${config.sops.placeholder."frp-token"}
        FRP_USER=${config.sops.placeholder."frp-user"}
      '';
      restartUnits = [ "frp-primary.service" ];
    };
  };

  services.frp = {
    instances.primary = {
      enable = true;
      role = "client";
      environmentFiles = [
        config.sops.templates."frp-primary.env".path
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
            name = "proxy_20260808172818_52a061f3"; # Xianyu Gebulin SimpleVoiceChat
            type = "udp";
            localPort = 6001;
            remotePort = 6001;
          }
        ];
      };
    };
  };

  systemd.services.frp-chml = {
    description = "ChmlFrp client";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      ExecStart = chmlfrpStart;
      LoadCredential = "api-token:${config.sops.secrets."frp-chml-user".path}";
      RuntimeDirectory = "frp-chml";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 15;

      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      PrivateDevices = true;
      PrivateMounts = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" ];
    };
  };
}
