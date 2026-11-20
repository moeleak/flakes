# A node on DN42 (lib/dn42.nix). Its addresses sit on the dummy interface
# `dn42`; each peering, the other nodes included, has its own WireGuard
# interface `dn42-<name>` with a link-local address, over which BIRD speaks
# MP-BGP (IPv4 with IPv6 next hops). BIRD installs the routes it learns with the
# node's own DN42 address as their source, so whatever the node itself opens
# reaches DN42: sing-box (the proxy node) takes the clients there.
#
# The node's eBGP peers are the files in peers/<node>/, one a peer, named by
# it:
#
#   # peers/lax/<name>.nix
#   {
#     asn = 4242420000;
#     endpoint = "host:port"; # left out if only they connect to us
#     publicKey = "…";
#     linkLocal = "fe80::…";  # theirs; ours is the node's `linkLocal`
#     port = 20000;           # ours; default 2 and their ASN's last 4 digits
#   }
#
# A peer's name becomes the interface dn42-<name>, so at most 10 characters.
#
# BIRD's configuration is bird.conf, after this node's values as constants
# and followed by a session per tunnel. It follows
# https://dn42.dev/howto/Bird2: ROA-filtered eBGP. stayrtr serves BIRD the
# registry's ROAs over RTR, from the export at dn42.burble.com, and BIRD
# filters the peers' routes again whenever they change.
# Secret: `dn42-wireguard/<name>`, the node's WireGuard private key.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.dn42;
  dn42 = import ../../../../lib/dn42.nix;
  proxy = import ../../../../lib/proxy.nix;
  node = dn42.nodes.${cfg.name};

  # Where stayrtr serves the ROAs to BIRD.
  rtrPort = 8282;

  # Every tunnel of this node: the other nodes, then its peers.
  others = lib.mapAttrs (name: other: {
    internal = true;
    asn = dn42.asn;
    endpoint = "${name}.${proxy.domain}:${toString dn42.internalPort}";
    port = dn42.internalPort;
    inherit (other) publicKey linkLocal;
  }) (removeAttrs dn42.nodes [ cfg.name ]);
  peersDir = ./peers + "/${cfg.name}";
  peerFiles = lib.optionalAttrs (builtins.pathExists peersDir) (
    lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".nix" file) (
      builtins.readDir peersDir
    )
  );
  peers = lib.mapAttrs' (
    file: _:
    let
      peer = import (peersDir + "/${file}");
    in
    lib.nameValuePair (lib.removeSuffix ".nix" file) (
      {
        internal = false;
        endpoint = null;
        # 2 followed by the last four digits of their ASN.
        port = 20000 + lib.mod peer.asn 10000;
      }
      // peer
    )
  ) peerFiles;
  tunnels = others // peers;

  interface = name: "dn42-${name}";
  protocolName = name: lib.replaceStrings [ "-" ] [ "_" ] name;

  bgpSession =
    name: tunnel:
    if tunnel.internal then
      ''
        protocol bgp ibgp_${protocolName name} from dnnodes {
          neighbor ${tunnel.linkLocal} as OWNAS;
          interface "${interface name}";
        }
      ''
    else
      ''
        protocol bgp dn42_${protocolName name} from dnpeers {
          neighbor ${tunnel.linkLocal} as ${toString tunnel.asn};
          interface "${interface name}";
        }
      '';

  # The node's values as BIRD constants, the configuration they go into
  # (bird.conf), then a session per tunnel.
  birdConfig = lib.concatStringsSep "\n" (
    [
      ''
        define OWNAS = ${toString dn42.asn};
        define OWNIP = ${node.ipv4};
        define OWNIPv6 = ${node.ipv6};
        define OWNNET = ${dn42.ipv4};
        define OWNNETv6 = ${dn42.ipv6};
        define OWNNETSET = [${dn42.ipv4}+];
        define OWNNETSETv6 = [${dn42.ipv6}+];
        define RTRPORT = ${toString rtrPort};
      ''
      (builtins.readFile ./bird.conf)
    ]
    ++ lib.mapAttrsToList bgpSession tunnels
  );
in
{
  options.my.services.dn42 = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        # A key of `nodes` in lib/dn42.nix.
        options.name = lib.mkOption { type = lib.types.enum (lib.attrNames dn42.nodes); };
      }
    );
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    assertions = lib.mapAttrsToList (name: _: {
      assertion = lib.stringLength (interface name) <= 15;
      message = "dn42: the interface of peer ${name}, ${interface name}, is longer than 15 characters.";
    }) tunnels;

    sops.secrets."dn42-wireguard/${cfg.name}" = {
      owner = "systemd-network";
      group = "systemd-network";
      mode = "0400";
      restartUnits = [ "systemd-networkd.service" ];
    };

    systemd.network = {
      # Forward between the tunnels; the RA client stays on, as set for eth0.
      config.networkConfig = {
        IPv4Forwarding = true;
        IPv6Forwarding = true;
      };

      netdevs = {
        "60-dn42".netdevConfig = {
          Kind = "dummy";
          Name = "dn42";
        };
      }
      // lib.mapAttrs' (
        name: tunnel:
        lib.nameValuePair "60-${interface name}" {
          netdevConfig = {
            Kind = "wireguard";
            Name = interface name;
          };
          wireguardConfig = {
            PrivateKeyFile = config.sops.secrets."dn42-wireguard/${cfg.name}".path;
            ListenPort = tunnel.port;
          };
          # No routes for AllowedIPs: BIRD installs them.
          wireguardPeers = [
            (
              {
                PublicKey = tunnel.publicKey;
                AllowedIPs = [
                  "0.0.0.0/0"
                  "::/0"
                ];
              }
              // lib.optionalAttrs (tunnel.endpoint != null) {
                Endpoint = tunnel.endpoint;
                PersistentKeepalive = 25;
              }
            )
          ];
        }
      ) tunnels;

      networks = {
        "60-dn42" = {
          matchConfig.Name = "dn42";
          address = [
            "${node.ipv4}/32"
            "${node.ipv6}/128"
          ];
          networkConfig.LinkLocalAddressing = "no";
          linkConfig.RequiredForOnline = "no";
        };
      }
      // lib.mapAttrs' (
        name: _:
        lib.nameValuePair "60-${interface name}" {
          matchConfig.Name = interface name;
          address = [ "${node.linkLocal}/64" ];
          networkConfig = {
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
            # Routes are asymmetric across peers.
            IPv4ReversePathFilter = "no";
          };
          linkConfig.RequiredForOnline = "no";
        }
      ) tunnels;
    };

    services.bird = {
      enable = true;
      config = birdConfig;
    };

    # stayrtr fetches the ROAs again every 10 minutes. It serves no metrics,
    # which would listen on every address.
    systemd.services.dn42-rtr = {
      description = "RTR server of the DN42 ROAs, for BIRD";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.stayrtr} -cache https://dn42.burble.com/roa/dn42_roa_46.json -bind 127.0.0.1:${toString rtrPort} -metrics.addr=";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };
}
