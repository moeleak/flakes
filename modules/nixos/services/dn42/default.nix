# A node on DN42 (lib/dn42.nix). Its addresses sit on the dummy interface
# `dn42`; each peering, the other nodes included, has its own WireGuard
# interface `dn42-<name>` with a link-local address, over which BIRD speaks
# MP-BGP (IPv4 with IPv6 next hops). BIRD installs the routes it learns with the
# node's own DN42 address as their source, so whatever the node itself opens
# reaches DN42: sing-box (the proxy node) takes the clients there.
#
# The BIRD configuration follows https://dn42.dev/howto/Bird2: ROA-filtered
# eBGP, with the ROA tables updated every 15 minutes from dn42.burble.com.
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

  # Where BIRD includes the ROA tables from, relative to /etc/bird/bird.conf.
  roaDir = "/var/lib/bird/roa";
  roaFiles = {
    v4 = "dn42_roa_bird2_4.conf";
    v6 = "dn42_roa_bird2_6.conf";
  };

  # Every tunnel of this node: the other nodes, then its peers.
  others = lib.mapAttrs (name: other: {
    internal = true;
    asn = dn42.asn;
    endpoint = "${name}.${proxy.domain}:${toString dn42.internalPort}";
    port = dn42.internalPort;
    inherit (other) publicKey linkLocal;
  }) (removeAttrs dn42.nodes [ cfg.name ]);
  peers = lib.mapAttrs (
    _: peer:
    {
      internal = false;
      endpoint = null;
      # 2 followed by the last four digits of their ASN.
      port = 20000 + lib.mod peer.asn 10000;
    }
    // peer
  ) node.peers;
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

  birdConfig = ''
    define OWNAS = ${toString dn42.asn};
    define OWNIP = ${node.ipv4};
    define OWNIPv6 = ${node.ipv6};
    define OWNNET = ${dn42.ipv4};
    define OWNNETv6 = ${dn42.ipv6};
    define OWNNETSET = [${dn42.ipv4}+];
    define OWNNETSETv6 = [${dn42.ipv6}+];

    router id OWNIP;

    protocol device {
      scan time 10;
    }

    function is_self_net() -> bool {
      return net ~ OWNNETSET;
    }

    function is_self_net_v6() -> bool {
      return net ~ OWNNETSETv6;
    }

    function is_valid_network() -> bool {
      return net ~ [
        172.20.0.0/14{21,29}, # dn42
        172.20.0.0/24{28,32}, # dn42 Anycast
        172.21.0.0/24{28,32}, # dn42 Anycast
        172.22.0.0/24{28,32}, # dn42 Anycast
        172.23.0.0/24{28,32}, # dn42 Anycast
        172.31.0.0/16+,       # ChaosVPN
        10.100.0.0/14+,       # ChaosVPN
        10.127.0.0/16+,       # neonetwork
        10.0.0.0/8{15,24}     # Freifunk.net
      ];
    }

    function is_valid_network_v6() -> bool {
      return net ~ [
        fd00::/8{44,64} # ULA address space as per RFC 4193
      ];
    }

    roa4 table dn42_roa;
    roa6 table dn42_roa_v6;

    protocol static {
      roa4 { table dn42_roa; };
      include "roa/${roaFiles.v4}";
    }

    protocol static {
      roa6 { table dn42_roa_v6; };
      include "roa/${roaFiles.v6}";
    }

    # Learned routes leave from this node's own address. The aggregates below
    # are only announced, and the node's addresses are on the dummy interface.
    protocol kernel {
      scan time 20;
      ipv4 {
        import none;
        export filter {
          if source ~ [RTS_STATIC, RTS_DEVICE] then reject;
          krt_prefsrc = OWNIP;
          accept;
        };
      };
    }

    protocol kernel {
      scan time 20;
      ipv6 {
        import none;
        export filter {
          if source ~ [RTS_STATIC, RTS_DEVICE] then reject;
          krt_prefsrc = OWNIPv6;
          accept;
        };
      };
    }

    protocol static {
      route OWNNET reject;
      ipv4 {
        import all;
        export none;
      };
    }

    protocol static {
      route OWNNETv6 reject;
      ipv6 {
        import all;
        export none;
      };
    }

    # This node's addresses, announced to the other nodes.
    protocol direct {
      interface "dn42";
      ipv4;
      ipv6;
    }

    template bgp dnpeers {
      local as OWNAS;
      path metric on;
      enable extended messages on;

      ipv4 {
        extended next hop on;
        import filter {
          if is_valid_network() && !is_self_net() then {
            if (roa_check(dn42_roa, net, bgp_path.last) != ROA_VALID) then {
              print "[dn42] ROA check failed for ", net, " ASN ", bgp_path.last;
              reject;
            } else accept;
          } else reject;
        };
        export filter {
          if is_valid_network() && source ~ [RTS_STATIC, RTS_BGP] then accept;
          else reject;
        };
        import limit 9000 action block;
      };

      ipv6 {
        import filter {
          if is_valid_network_v6() && !is_self_net_v6() then {
            if (roa_check(dn42_roa_v6, net, bgp_path.last) != ROA_VALID) then {
              print "[dn42] ROA check failed for ", net, " ASN ", bgp_path.last;
              reject;
            } else accept;
          } else reject;
        };
        export filter {
          if is_valid_network_v6() && source ~ [RTS_STATIC, RTS_BGP] then accept;
          else reject;
        };
        import limit 9000 action block;
      };
    }

    # The other nodes: everything learned, and each node's own addresses.
    template bgp dnnodes {
      local as OWNAS;
      direct;
      enable extended messages on;

      ipv4 {
        next hop self;
        extended next hop on;
        import all;
        export where source ~ [RTS_BGP, RTS_DEVICE];
      };

      ipv6 {
        next hop self;
        import all;
        export where source ~ [RTS_BGP, RTS_DEVICE];
      };
    }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList bgpSession tunnels)}
  '';
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
      # The ROA tables are only there at run time.
      preCheckConfig = ''
        mkdir roa
        touch roa/${roaFiles.v4} roa/${roaFiles.v6}
      '';
    };

    environment.etc."bird/roa".source = roaDir;
    systemd.tmpfiles.rules = [
      "d ${roaDir} 0755 root root -"
      "f ${roaDir}/${roaFiles.v4} 0644 root root -"
      "f ${roaDir}/${roaFiles.v6} 0644 root root -"
    ];

    systemd.services.dn42-roa = {
      description = "Update the DN42 ROA tables of BIRD";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "bird.service"
      ];
      path = [
        pkgs.curl
        config.services.bird.package
      ];
      serviceConfig.Type = "oneshot";
      script =
        lib.concatMapStrings (file: ''
          curl -fsSL --retry 3 -o ${roaDir}/${file}.new https://dn42.burble.com/roa/${file}
          mv ${roaDir}/${file}.new ${roaDir}/${file}
        '') (lib.attrValues roaFiles)
        + ''
          birdc configure
        '';
    };
    systemd.timers.dn42-roa = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "15m";
      };
    };
  };
}
