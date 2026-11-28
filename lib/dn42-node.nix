# A node on DN42 (lib/dn42.nix): its tunnels, to the other nodes and to its
# eBGP peers (modules/nixos/services/dn42/peers/<name>/), and BIRD's
# configuration for them. Read by the NixOS nodes
# (modules/nixos/services/dn42) and by the VMs' cloud-init
# (modules/nixos/services/vms), so that all run the same BIRD.
#
# `rtr`: whether BIRD takes the ROAs from stayrtr, on `rtrPort`. A node
# without eBGP peers, such as a VM, has no use for them.
{
  lib,
  name,
  rtr ? true,
}:
let
  dn42 = import ./dn42.nix;
  node = dn42.nodes.${name};

  # Where stayrtr serves the ROAs to BIRD.
  rtrPort = 8282;

  # Every tunnel of this node: the other nodes, but those that wait for it as
  # it waits for them, then its peers. Both ends of a tunnel between nodes
  # listen on the same port (lib/dn42.nix).
  reachable = _: other: node.endpoint != null || other.endpoint != null;
  others = lib.mapAttrs (
    _: other:
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
  ) (lib.filterAttrs reachable (removeAttrs dn42.nodes [ name ]));
  peersDir = ../modules/nixos/services/dn42/peers + "/${name}";
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
        regions = null;
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
          ${lib.optionalString (tunnel.regions != null) (
            lib.replaceStrings [ "\n" ] [ "\n  " ] (regionChannels tunnel)
          )}
        }
      '';

  # A peer with `regions`, far from the other nodes: its routes lose to
  # theirs (a lower local preference, which the other nodes take over),
  # but for its own and those from these DN42 regions, the communities
  # (64511, <region>) of https://dn42.dev/howto/BGP-communities. Without
  # it, BGP takes such a peer wherever its path is no longer than theirs, as
  # an eBGP route wins over iBGP ones of the same length.
  regionChannels =
    tunnel:
    let
      near = lib.concatStringsSep " || " (
        [ "bgp_path.last = ${toString tunnel.asn}" ]
        ++ map (region: "(64511, ${toString region}) ~ bgp_community") tunnel.regions
      );
      channel = family: valid: ''
        ${family} {
          import filter {
            if !${valid}() then reject;
            ebgp_med();
            if !(${near}) then bgp_local_pref = 50;
            accept;
          };
        };'';
    in
    channel "ipv4" "ebgp_valid" + "\n" + channel "ipv6" "ebgp_valid_v6";

  # stayrtr notifies BIRD of each change. If BIRD starts before stayrtr
  # listens, it tries again soon, and if stayrtr goes away, it keeps the
  # ROAs it has for two days.
  rpki = ''
    protocol rpki rpki_stayrtr {
      roa4 { table roa_v4; };
      roa6 { table roa_v6; };
      remote 127.0.0.1 port RTRPORT;
      retry keep 30;
      expire keep 172800;
    }
  '';

  # The node's values as BIRD constants, the configuration they go into
  # (bird.conf), stayrtr, then a session per tunnel.
  birdConfig = lib.concatStringsSep "\n" (
    [
      (
        ''
          define OWNAS = ${toString dn42.asn};
          define OWNIP = ${node.ipv4};
          define OWNIPv6 = ${node.ipv6};
          define OWNNET = ${dn42.ipv4};
          define OWNNETv6 = ${dn42.ipv6};
          define OWNNETSET = [${dn42.ipv4}+];
          define OWNNETSETv6 = [${dn42.ipv6}+];
          define OWNREGION = ${toString (node.region or 0)};
        ''
        + lib.optionalString rtr ''
          define RTRPORT = ${toString rtrPort};
        ''
      )
      (builtins.readFile ../modules/nixos/services/dn42/bird.conf)
    ]
    ++ lib.optional rtr rpki
    ++ lib.mapAttrsToList bgpSession tunnels
  );
in
{
  inherit
    node
    others
    tunnels
    interface
    rtrPort
    birdConfig
    ;
}
