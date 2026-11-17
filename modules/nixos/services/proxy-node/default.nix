# A Hysteria 2 node that the sing-box clients use (lib/proxy.nix lists the
# nodes and their users). It serves:
#
# - Hysteria 2 on UDP `port` without obfuscation, and with Salamander on
#   `obfsPort`, which every UDP port in `hopPorts` is redirected to;
# - https://<name>.leak.moe/config?token=<token>, each user's sing-box profile
#   with all of that user's nodes, behind Caddy.
#
# Secrets: `sing-box-hysteria-<name>-{password,obfs-password}` (the flake's own
# clients log in as "flakes"), `sing-box-hysteria-<name>-tls` (certificate and
# key; clients pin its public key as `-pin`), and `sing-box-users.<user>`
# (`token`, and a password per node).
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.my.services.proxy-node;
  proxy = import ../../../../lib/proxy.nix;
  inherit (proxy.hysteria) hopPorts;

  prefix = "sing-box-hysteria-${cfg.name}";
  secret = name: { _secret = config.sops.secrets.${name}.path; };
  configPort = 8090;

  allUsers = lib.unique (lib.concatMap (node: node.users) (lib.attrValues proxy.nodes));
  nodesOf = user: lib.filter (node: lib.elem user proxy.nodes.${node}.users) (lib.attrNames proxy.nodes);

  hysteria = {
    type = "hysteria2";
    listen = "::";
    users = [
      {
        name = "flakes";
        password = secret "${prefix}-password";
      }
    ]
    ++ map (user: {
      name = user;
      password = secret "sing-box-users/${user}/${cfg.name}";
    }) proxy.nodes.${cfg.name}.users;
    tls = {
      enabled = true;
      certificate = secret "${prefix}-tls/certificate";
      key = secret "${prefix}-tls/key";
    };
  };

  # What the config server hands out, rendered with the secrets at start.
  profiles = utils.genJqSecretsReplacement { loadCredential = true; } (lib.genAttrs allUsers (user: {
    token = secret "sing-box-users/${user}/token";
    config = import ./client.nix {
      inherit proxy secret user;
      nodes = nodesOf user;
    };
  })) "/run/proxy-config/users.json";
in
{
  options.my.services.proxy-node = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          # A key of `nodes` in lib/proxy.nix.
          name = lib.mkOption { type = lib.types.enum (lib.attrNames proxy.nodes); };
          # The interface whose hopPorts are redirected.
          interface = lib.mkOption {
            type = lib.types.str;
            default = "eth0";
          };
        };
      }
    );
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    assertions = [
      {
        assertion = config.my.services.sing-box == null;
        message = "my.services.proxy-node replaces the sing-box client; set my.services.sing-box = null.";
      }
    ];

    sops.secrets = lib.genAttrs (
      [
        "${prefix}-password"
        "${prefix}-obfs-password"
        "${prefix}-tls/certificate"
        "${prefix}-tls/key"
      ]
      ++ lib.concatMap (
        user:
        [ "sing-box-users/${user}/token" ]
        ++ lib.concatMap (node: [
          "sing-box-users/${user}/${node}"
          "sing-box-hysteria-${node}-server"
          "sing-box-hysteria-${node}-obfs-password"
          "sing-box-hysteria-${node}-pin"
        ]) (nodesOf user)
      ) allUsers
    ) (_: {
      restartUnits = [
        "sing-box.service"
        "proxy-config.service"
      ];
    });

    services.sing-box = {
      enable = true;
      settings = {
        log.level = "info";
        dns.servers = [
          {
            type = "local";
            tag = "local";
          }
        ];
        inbounds = [
          (
            hysteria
            // {
              tag = "hysteria-in";
              listen_port = proxy.hysteria.port;
            }
          )
          (
            hysteria
            // {
              tag = "hysteria-obfs-in";
              listen_port = proxy.hysteria.obfsPort;
              obfs = {
                type = "salamander";
                password = secret "${prefix}-obfs-password";
              };
            }
          )
        ];
        outbounds = [
          {
            type = "direct";
            tag = "direct";
          }
        ];
        route = {
          final = "direct";
          default_domain_resolver = "local";
        };
      };
    };

    # Port hopping: the kernel sends every port of the range to the obfuscated
    # listener. Docker keeps its own iptables-nft tables, so a reload replaces
    # only this table instead of flushing the ruleset.
    networking.nftables = {
      enable = true;
      flushRuleset = false;
      tables.hysteria-port-hopping = {
        family = "inet";
        content = ''
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            iifname "${cfg.interface}" udp dport ${toString hopPorts.from}-${toString hopPorts.to} redirect to :${toString proxy.hysteria.obfsPort}
          }
        '';
      };
    };

    # https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
    boot.kernel.sysctl = {
      "net.core.rmem_max" = 7500000;
      "net.core.wmem_max" = 7500000;
    };

    systemd.services.proxy-config = {
      description = "Per-user sing-box profiles";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStartPre = pkgs.writeShellScript "proxy-config-render" ''
          set -euo pipefail
          ${profiles.script}
          # Refuse to serve a profile that sing-box would reject.
          for user in $(${lib.getExe pkgs.jq} -r 'keys[]' /run/proxy-config/users.json); do
            ${lib.getExe pkgs.jq} --arg user "$user" '.[$user].config' /run/proxy-config/users.json > /run/proxy-config/check.json
            ${lib.getExe pkgs.sing-box} check -c /run/proxy-config/check.json || { echo "profile of $user is invalid" >&2; exit 1; }
          done
          rm /run/proxy-config/check.json
        '';
        ExecStart = "${
          lib.getExe (pkgs.callPackage ../../../../pkgs/proxy-config { })
        } -listen 127.0.0.1:${toString configPort} -users /run/proxy-config/users.json";
        LoadCredential = profiles.credentials;
        Restart = "on-failure";

        DynamicUser = true;
        RuntimeDirectory = "proxy-config";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = "/run/proxy-config";
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        UMask = "0077";
      };
    };

    services.caddy = {
      enable = true;
      virtualHosts."${cfg.name}.${proxy.domain}" = {
        # The query string carries the user's token.
        logFormat = "output discard";
        extraConfig = ''
          handle /config {
            reverse_proxy 127.0.0.1:${toString configPort}
          }
          handle {
            respond 404
          }
        '';
      };
    };
  };
}
