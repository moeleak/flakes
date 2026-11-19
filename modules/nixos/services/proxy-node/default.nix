# A proxy node that the sing-box clients use (lib/proxy.nix lists the nodes and
# their users). It serves:
#
# - VLESS with XTLS Vision on TCP `vless.port`, over TLS with a Let's Encrypt
#   certificate for <name>.leak.moe that sing-box obtains itself, answering the
#   HTTP challenge behind Caddy's port 80;
# - on the node named by `profiles.node` only:
#   https://<profiles.host>/query?token=<token>, each user's sing-box profile
#   with all of that user's nodes, behind Caddy; `&tailscale=true` adds a
#   Tailscale endpoint and `&lab=true` the Lab relay. Browsers get a QR code
#   to import it into the sing-box apps, unless `&qr-code=false`.
#
# Secrets: `sing-box-vless-uuid` (the flake's own clients, user "flakes") and
# `sing-box-users.<user>` (`uuid`, and the profile `token`).
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

  fqdn = "${cfg.name}.${proxy.domain}";
  secret = name: { _secret = config.sops.secrets.${name}.path; };
  configPort = 8090;
  # Where sing-box answers the ACME HTTP challenge, forwarded from port 80.
  acmePort = 18080;
  serveProfiles = cfg.name == proxy.profiles.node;
  onDn42 = config.my.services.dn42 != null;
  proxyConfig = pkgs.callPackage ../../../../pkgs/proxy-config { };

  allUsers = lib.unique (lib.concatMap (node: node.users) (lib.attrValues proxy.nodes));
  nodesOf = user: lib.filter (node: lib.elem user proxy.nodes.${node}.users) (lib.attrNames proxy.nodes);

  # The profile's switches, and every combination of them, named as the
  # server looks them up: the enabled ones in this order, joined with commas.
  switches = [
    "lab"
    "tailscale"
  ];
  combinations = lib.foldr (switch: rest: rest ++ map (on: [ switch ] ++ on) rest) [ [ ] ] switches;

  # What the config server hands out, rendered with the secrets at start.
  profiles = utils.genJqSecretsReplacement { loadCredential = true; } (lib.genAttrs allUsers (user: {
    token = secret "sing-box-users/${user}/token";
    configs = lib.listToAttrs (
      map (on: {
        name = lib.concatStringsSep "," on;
        value = import ./client.nix {
          inherit proxy secret user;
          nodes = nodesOf user;
          lab = lib.elem "lab" on;
          tailscale = lib.elem "tailscale" on;
        };
      }) combinations
    );
  })) "/run/proxy-config/users.json";
in
{
  options.my.services.proxy-node = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        # A key of `nodes` in lib/proxy.nix.
        options.name = lib.mkOption { type = lib.types.enum (lib.attrNames proxy.nodes); };
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

    sops.secrets =
      let
        # Read by this node's sing-box.
        nodeSecrets = [
          "sing-box-vless-uuid"
        ]
        ++ map (user: "sing-box-users/${user}/uuid") proxy.nodes.${cfg.name}.users;
        # Rendered into the profiles.
        profileSecrets = lib.optionals serveProfiles (
          [ "sing-box-lab-password" ]
          ++ lib.concatMap (user: [
            "sing-box-users/${user}/token"
            "sing-box-users/${user}/uuid"
          ]) allUsers
        );
      in
      lib.genAttrs (lib.unique (nodeSecrets ++ profileSecrets)) (name: {
        restartUnits =
          lib.optional (lib.elem name nodeSecrets) "sing-box.service"
          ++ lib.optional (lib.elem name profileSecrets) "proxy-config.service";
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
        ]
        ++ lib.optionals onDn42 [
          {
            # The anycast recursive resolver, reached over DN42.
            type = "udp";
            tag = "dn42";
            server = "172.20.0.53";
          }
        ];
        certificate_providers = [
          {
            type = "acme";
            tag = "acme";
            domain = [ fqdn ];
            data_directory = "/var/lib/sing-box/acme";
            # Caddy holds port 443.
            disable_tls_alpn_challenge = true;
            alternative_http_port = acmePort;
          }
        ];
        inbounds = [
          {
            type = "vless";
            tag = "vless-in";
            listen = "::";
            listen_port = proxy.vless.port;
            users = [
              {
                name = "flakes";
                uuid = secret "sing-box-vless-uuid";
                inherit (proxy.vless) flow;
              }
            ]
            ++ map (user: {
              name = user;
              uuid = secret "sing-box-users/${user}/uuid";
              inherit (proxy.vless) flow;
            }) proxy.nodes.${cfg.name}.users;
            tls = {
              enabled = true;
              # Negotiate like an ordinary HTTPS server.
              alpn = [
                "h2"
                "http/1.1"
              ];
              certificate_provider = "acme";
            };
          }
        ];
        outbounds = [
          {
            type = "direct";
            tag = "direct";
          }
        ];
        route = {
          # The clients send DN42 here by name (lib/dn42.nix); BIRD's routes
          # take the direct outbound there.
          rules = lib.optionals onDn42 [
            {
              domain_suffix = [ "dn42" ];
              action = "resolve";
              server = "dn42";
            }
          ];
          final = "direct";
          default_domain_resolver = "local";
        };
      };
    };

    systemd.services.proxy-config = lib.mkIf serveProfiles {
      description = "Per-user sing-box profiles";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStartPre = pkgs.writeShellScript "proxy-config-render" ''
          set -euo pipefail
          ${profiles.script}
          # Refuse to serve a profile that sing-box would reject.
          for user in $(${lib.getExe pkgs.jq} -r 'keys[]' /run/proxy-config/users.json); do
            for variant in ${lib.escapeShellArgs (map (lib.concatStringsSep ",") combinations)}; do
              ${lib.getExe pkgs.jq} --arg user "$user" --arg variant "$variant" '.[$user].configs[$variant]' /run/proxy-config/users.json > /run/proxy-config/check.json
              ${lib.getExe pkgs.sing-box} check -c /run/proxy-config/check.json || { echo "profile '$variant' of $user is invalid" >&2; exit 1; }
            done
          done
          rm /run/proxy-config/check.json
        '';
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe proxyConfig)
          "-listen 127.0.0.1:${toString configPort}"
          "-users /run/proxy-config/users.json"
          "-url https://${proxy.profiles.host}/query"
          "-assets ${proxyConfig.web}"
        ];
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
      virtualHosts = {
        "http://${fqdn}".extraConfig = ''
          handle /.well-known/acme-challenge/* {
            reverse_proxy 127.0.0.1:${toString acmePort}
          }
          handle {
            respond 404
          }
        '';
      }
      // lib.optionalAttrs serveProfiles {
        ${proxy.profiles.host} = {
          # The query string carries the user's token.
          logFormat = "output discard";
          extraConfig = ''
            handle /query {
              reverse_proxy 127.0.0.1:${toString configPort}
            }
            handle /assets/* {
              reverse_proxy 127.0.0.1:${toString configPort}
            }
            handle {
              respond 404
            }
          '';
        };
      };
    };
  };
}
