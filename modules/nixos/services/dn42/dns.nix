# The zone `domain` (lib/dn42.nix), which data/dns/moeleak.dn42 in the DN42
# registry delegates to the nodes. Each serves all of it with NSD on its own
# DN42 addresses, as its `nameserver` (ns1.moeleak.dn42, ...), and is in it
# by name (an4.moeleak.dn42, ...). Nothing transfers the zone, so its serial
# need not change with it.
{ config, lib, ... }:
let
  cfg = config.my.services.dn42;
  dn42 = import ../../../../lib/dn42.nix;
  node = dn42.nodes.${cfg.name};

  addresses = name: n: ''
    ${name} A ${n.ipv4}
    ${name} AAAA ${n.ipv6}
  '';

  zone = ''
    $ORIGIN ${dn42.domain}.
    $TTL 300
    @ SOA ${node.nameserver} hostmaster 2026112001 7200 1800 1209600 300
  ''
  + lib.concatMapStrings (n: "@ NS ${n.nameserver}\n") (lib.attrValues dn42.nodes)
  + lib.concatStrings (
    lib.mapAttrsToList (name: n: addresses n.nameserver n + addresses name n) dn42.nodes
  );
in
{
  config = lib.mkIf (cfg != null) {
    services.nsd = {
      enable = true;
      interfaces = [
        node.ipv4
        node.ipv6
      ];
      # The addresses sit on the dummy `dn42`, which may come up after NSD.
      ipFreebind = true;
      zones."${dn42.domain}.".data = zone;
    };
  };
}
