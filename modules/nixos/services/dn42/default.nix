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
# peers' tunnels go by sing-box's other rules.
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
# and followed by stayrtr and a session per tunnel (lib/dn42-node.nix, which
# the VMs on DN42 share; modules/nixos/services/vms). It follows
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
  nodeLib = import ../../../../lib/dn42-node.nix {
    inherit lib;
    inherit (cfg) name;
  };
  inherit (nodeLib)
    node
    others
    tunnels
    interface
    rtrPort
    birdConfig
    ;

  # sing-box's auto_redirect_output_mark (0x2024, its default), which its
  # TUN lets out; see the top.
  singBoxOutputMark = 8228;

  viaProxy = node.viaProxy or false;
  proxy = import ../../../../lib/proxy.nix;

  # The tunnels' endpoints given by name rather than by address.
  endpointHosts = lib.unique (
    lib.filter (host: builtins.match "[0-9.]+|\\[.*]" host == null) (
      map (tunnel: lib.head (builtins.match "(.*):[0-9]+" tunnel.endpoint)) (
        lib.filter (tunnel: tunnel.endpoint != null) (lib.attrValues tunnels)
      )
    )
  );

  pskSecret = name: "dn42-wireguard-psk/${name}";
in
{
  imports = [
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
    # them; they keep `nameservers`. Docker's networks, by default each a /16
    # from 172.17.0.0 to 172.31.0.0, would take DN42's ranges (lib/dn42.nix),
    # and Docker masquerades whatever leaves one of them for another
    # interface: the node's own address and what it forwards for its peers
    # would leave the tunnels as the host's. They take the rest of
    # 172.16.0.0/12 instead, beside Docker's default 192.168.0.0/16.
    virtualisation.docker.daemon.settings = lib.mkIf config.virtualisation.docker.enable {
      dns = lib.mkDefault config.networking.nameservers;
      default-address-pools =
        map
          (base: {
            inherit base;
            size = 16;
          })
          [
            "172.16.0.0/14"
            "172.24.0.0/14"
            "172.28.0.0/15"
            "172.30.0.0/16"
          ]
        ++ [
          {
            base = "192.168.0.0/16";
            size = 20;
          }
        ];
    };

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
