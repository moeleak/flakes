# A node on DN42 (lib/dn42.nix). Its addresses sit on the dummy interface
# `dn42`; each peering, the other nodes included, has its own WireGuard
# interface `dn42-<name>` with a link-local address, over which BIRD speaks
# MP-BGP (IPv4 with IPv6 next hops). BIRD installs the routes it learns with the
# node's own DN42 address as their source, so whatever the node itself opens
# reaches DN42: sing-box (the proxy node) takes the clients there.
#
# A node without an `endpoint` (lib/dn42.nix) connects to the other nodes,
# which wait for it; two such nodes have no tunnel between them, and the nodes
# they both connect to reflect each one's routes to the other (`rr client`).
# On a node that also runs the sing-box client, its TUN leaves DN42 to these
# routes (route_exclude_address), and the tunnels mark their packets as
# sing-box marks its own, so that auto_redirect lets them out past the TUN.
# Their endpoints' names resolve to real addresses there, not to sing-box's
# FakeIPs, which lead nowhere past the TUN.
#
# A `viaProxy` node's tunnels to the other nodes go into the TUN instead,
# unmarked, and sing-box takes each one, by its port, over VLESS to the proxy
# node at its other end, whose sing-box hands it to WireGuard there. Its eBGP
# peers' tunnels, if it had any, would take sing-box's default route.
#
# On a host whose network NetworkManager runs (Lab), systemd-networkd runs
# beside it for the DN42 interfaces alone, which NetworkManager leaves to it,
# and leaves the other routes and rules alone.
#
# The node's eBGP peers are the files in peers/<node>/, one a peer, named by
# it:
#
#   # peers/an4/<name>.nix
#   {
#     asn = 4242420000;
#     endpoint = "host:port"; # left out if only they connect to us
#     publicKey = "…";
#     linkLocal = "fe80::…";  # theirs
#     port = 20000;           # ours; default 2 and their ASN's last 4 digits
#     localLinkLocal = "fe80::…"; # ours, if not the node's `linkLocal`
#     presharedKey = true;    # dn42-wireguard-psk/<name> in secrets/dn42.yaml
#   }
#
# A peer's name becomes the interface dn42-<name>, so at most 10 characters.
#
# BIRD's configuration is bird.conf, after this node's values as constants
# and followed by a session per tunnel. It follows
# https://dn42.dev/howto/Bird2: ROA-filtered eBGP. stayrtr serves BIRD the
# registry's ROAs over RTR, from the export at dn42.burble.com, and BIRD
# filters the peers' routes again whenever they change.
# Secrets: `dn42-wireguard/<name>`, the node's WireGuard private key, and
# `dn42-wireguard-psk/<peer>` for a peer with `presharedKey`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.dn42;
  dn42 = import ../../../../lib/dn42.nix;
  node = dn42.nodes.${cfg.name};

  # Where stayrtr serves the ROAs to BIRD.
  rtrPort = 8282;

  # sing-box's auto_redirect_output_mark (0x2024, its default), which its
  # TUN lets out; see the top.
  singBoxOutputMark = 8228;

  viaProxy = node.viaProxy or false;
  proxy = import ../../../../lib/proxy.nix;

  # Every tunnel of this node: the other nodes, but those that wait for it as
  # it waits for them, then its peers. Both ends of a tunnel between nodes
  # listen on the same port (lib/dn42.nix).
  reachable = _: other: node.endpoint != null || other.endpoint != null;
  others = lib.mapAttrs (
    name: other:
    let
      port = dn42.internalPort + node.id + other.id - 3;
    in
    {
      internal = true;
      # This node waits for the other, which connects to the others: it
      # reflects that node's routes to them, and theirs to it.
      reflect = node.endpoint != null && other.endpoint == null;
      asn = dn42.asn;
      endpoint = if other.endpoint == null then null else "${other.endpoint}:${toString port}";
      inherit port;
      localLinkLocal = node.linkLocal;
      presharedKey = false;
      inherit (other) publicKey linkLocal;
    }
  ) (lib.filterAttrs reachable (removeAttrs dn42.nodes [ cfg.name ]));
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
        localLinkLocal = node.linkLocal;
        presharedKey = false;
      }
      // peer
    )
  ) peerFiles;
  tunnels = others // peers;

  # The tunnels' endpoints given by name rather than by address.
  endpointHosts = lib.unique (
    lib.filter (host: builtins.match "[0-9.]+|\\[.*]" host == null) (
      map (tunnel: lib.head (builtins.match "(.*):[0-9]+" tunnel.endpoint)) (
        lib.filter (tunnel: tunnel.endpoint != null) (lib.attrValues tunnels)
      )
    )
  );

  interface = name: "dn42-${name}";
  pskSecret = name: "dn42-wireguard-psk/${name}";
  protocolName = name: lib.replaceStrings [ "-" ] [ "_" ] name;

  bgpSession =
    name: tunnel:
    if tunnel.internal then
      ''
        protocol bgp ibgp_${protocolName name} from ibgp_node {
          neighbor ${tunnel.linkLocal} as OWNAS;
          interface "${interface name}";
          ${lib.optionalString tunnel.reflect "rr client;"}
        }
      ''
    else
      ''
        protocol bgp ebgp_${protocolName name} from ebgp_peer {
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
  imports = [
    ./archive.nix
    ./dns.nix
    ./mail.nix
  ];

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
    assertions =
      lib.mapAttrsToList (name: _: {
        assertion = lib.stringLength (interface name) <= 15;
        message = "dn42: the interface of peer ${name}, ${interface name}, is longer than 15 characters.";
      }) tunnels
      ++ lib.mapAttrsToList (name: tunnel: {
        assertion = lib.length (lib.filter (t: t.port == tunnel.port) (lib.attrValues tunnels)) == 1;
        message = "dn42: tunnel ${name} of ${cfg.name} listens on port ${toString tunnel.port}, as another of its tunnels does.";
      }) tunnels
      ++ lib.optionals viaProxy (
        [
          {
            assertion = config.my.services.sing-box != null;
            message = "dn42: ${cfg.name} reaches the other nodes through the sing-box client (viaProxy), which it doesn't run.";
          }
        ]
        ++ lib.mapAttrsToList (name: _: {
          assertion = proxy.nodes ? ${name} && dn42.nodes.${name}.endpoint != null;
          message = "dn42: ${cfg.name} reaches ${name} over VLESS (viaProxy), but ${name} is no proxy node with an endpoint.";
        }) others
      );

    # The node's WireGuard key, and the preshared keys of the peers that use
    # one.
    sops.secrets =
      let
        secret = {
          owner = "systemd-network";
          group = "systemd-network";
          mode = "0400";
          restartUnits = [ "systemd-networkd.service" ];
        };
      in
      {
        "dn42-wireguard/${cfg.name}" = secret;
      }
      // lib.mapAttrs' (name: _: lib.nameValuePair (pskSecret name) secret) (
        lib.filterAttrs (_: tunnel: tunnel.presharedKey) tunnels
      );

    systemd.network = {
      enable = true;
      # Forward between the tunnels; the RA client stays on, as set for eth0.
      config.networkConfig = {
        IPv4Forwarding = true;
        IPv6Forwarding = true;
      }
      // lib.optionalAttrs config.networking.networkmanager.enable {
        ManageForeignRoutes = false;
        ManageForeignRoutingPolicyRules = false;
      };
      # NetworkManager's own wait-online says when the network is up.
      wait-online.enable = lib.mkIf config.networking.networkmanager.enable false;

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
          }
          // lib.optionalAttrs (config.my.services.sing-box != null && !viaProxy) {
            FirewallMark = singBoxOutputMark;
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
              // lib.optionalAttrs tunnel.presharedKey {
                PresharedKeyFile = config.sops.secrets.${pskSecret name}.path;
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
        name: tunnel:
        lib.nameValuePair "60-${interface name}" {
          matchConfig.Name = interface name;
          address = [ "${tunnel.localLinkLocal}/64" ];
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

    # DN42's names, and the reverse names of its ranges, go to its anycast
    # resolver; the rest goes to `nameservers` and the links' servers as
    # before. A delegate rather than the servers of the link `dn42`: resolved
    # sends a link's queries out of that link, and the dummy drops them.
    services.resolved = {
      enable = true;
      settings.Resolve.LLMNR = false;
      dnsDelegates.dn42.Delegate = {
        DNS = [
          "172.20.0.53"
          "fd42:d42:d42:53::1"
        ];
        Domains = [
          "~dn42"
          "~10.in-addr.arpa"
          "~20.172.in-addr.arpa"
          "~21.172.in-addr.arpa"
          "~22.172.in-addr.arpa"
          "~23.172.in-addr.arpa"
          "~d.f.ip6.arpa"
        ];
      };
    };

    networking.networkmanager.unmanaged = [ "interface-name:dn42*" ];

    # Under resolved, the containers would get all its servers, DN42's among
    # them; they keep `nameservers`.
    virtualisation.docker.daemon.settings.dns = lib.mkIf config.virtualisation.docker.enable (
      lib.mkDefault config.networking.nameservers
    );

    services.bird = {
      enable = true;
      config = birdConfig;
    };

    # The endpoints' names, from the server the clients resolve the proxy
    # nodes with, before sing-box's other rules hand out FakeIPs; see the top.
    services.sing-box.settings.dns.rules =
      lib.mkIf (config.my.services.sing-box != null && endpointHosts != [ ])
        (
          lib.mkBefore [
            {
              domain = endpointHosts;
              server = "doh-cn";
            }
          ]
        );

    # A viaProxy node's tunnels, each by its port to the proxy node it leads
    # to, before any other rule.
    services.sing-box.settings.route.rules = lib.mkIf viaProxy (
      lib.mkBefore (
        lib.mapAttrsToList (name: tunnel: {
          network = "udp";
          port = tunnel.port;
          outbound = name;
        }) others
      )
    );

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
