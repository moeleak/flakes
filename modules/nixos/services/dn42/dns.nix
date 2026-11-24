# The zone `domain` (lib/dn42.nix), which data/dns/moeleak.dn42 in the DN42
# registry delegates to the nodes with a `nameserver`, the zone of
# `archive.domain`, which data/dns/archive.dn42 delegates to them too and
# which names the node `archive.node` (archive.nix), and the reverse zones of
# the network's ranges, which its inetnum and inet6num delegate to them (their
# `nserver`s). Each of them serves all of them with NSD on its own DN42
# addresses, as that nameserver (ns1.moeleak.dn42, ...). Every node is in them
# by name (an4.moeleak.dn42, ...), as is mail.moeleak.dn42, the domain's MX,
# by the addresses of its own on the node that takes its mail (mail.nix).
# Nothing transfers the zones, so their serials need not change with them.
#
# DN42 delegates the reverse names of an IPv4 range smaller than a /24 as RFC
# 2317 has it: 65.122.23.172.in-addr.arpa is a CNAME of
# 65.64/26.122.23.172.in-addr.arpa, in the zone 64/26.122.23.172.in-addr.arpa,
# which is ours. NixOS's NSD module names a zone's store path after it, which
# can't hold the "/", so that zone is configured here, its file copied to NSD's
# directory.
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
  nameservers = lib.filter (n: n.nameserver != null) (lib.attrValues dn42.nodes);
  fqdn = name: "${name}.${dn42.domain}.";

  # A zone's start: this node as its primary, then the nameservers.
  start =
    origin:
    ''
      $ORIGIN ${origin}
      $TTL 300
      @ SOA ${fqdn node.nameserver} ${fqdn "hostmaster"} 2026112401 7200 1800 1209600 300
    ''
    + lib.concatMapStrings (n: "@ NS ${fqdn n.nameserver}\n") nameservers;

  addresses = name: n: ''
    ${name} A ${n.ipv4}
    ${name} AAAA ${n.ipv6}
  '';
  # A TXT record's strings, of at most 255 characters each.
  strings =
    s:
    if lib.stringLength s <= 255 then
      ''"${s}"''
    else
      ''"${lib.substring 0 255 s}" '' + strings (lib.substring 255 (lib.stringLength s) s);
  inherit (dn42.mail) dkim;

  # mail.<domain>, the MX, which alone sends the domain's mail (SPF) and greets
  # with its own name (SPF of that name, which receivers may check as the
  # HELO's), and signs it (DKIM); mail that passes neither is to be
  # quarantined, and reports go to postmaster@ (DMARC).
  zone =
    start "${dn42.domain}."
    + ''
      @ MX 10 mail
      @ TXT "v=spf1 mx -all"
      mail TXT "v=spf1 a -all"
      ${dkim.selector}._domainkey TXT ${strings "v=DKIM1; k=rsa; p=${dkim.publicKey}"}
      _dmarc TXT "v=DMARC1; p=quarantine; rua=mailto:postmaster@${dn42.domain}"
    ''
    + addresses "mail" dn42.mail
    + lib.concatMapStrings (n: addresses n.nameserver n) nameservers
    + lib.concatStrings (lib.mapAttrsToList addresses dn42.nodes);

  # The archive, at the zone's apex and as www, by its node's addresses.
  archiveZone =
    start "${dn42.archive.domain}."
    + addresses "@" dn42.nodes.${dn42.archive.node}
    + ''
      www CNAME @
    '';

  # Each node's addresses name it, in the reverse zones, and the mail's name
  # it.
  pointers =
    name:
    lib.concatStrings (
      lib.mapAttrsToList (n: v: "${name v} PTR ${fqdn n}\n") (dn42.nodes // { inherit (dn42) mail; })
    );

  # 64/26.122.23.172.in-addr.arpa for 172.23.122.64/26, longer than a /24.
  v4 = builtins.match "([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)/([0-9]+)" dn42.ipv4;
  v4Origin = "${lib.elemAt v4 3}/${lib.elemAt v4 4}.${lib.elemAt v4 2}.${lib.elemAt v4 1}.${lib.elemAt v4 0}.in-addr.arpa.";
  v4Zone = start v4Origin + pointers (n: lib.last (lib.splitString "." n.ipv4));
  # Checked as the module checks its zones.
  v4ZoneFile = pkgs.runCommand "nsd-zone-rfc2317" { } ''
    ${pkgs.buildPackages.nsd}/sbin/nsd-checkzone ${lib.escapeShellArg v4Origin} ${pkgs.writeText "zone" v4Zone}
    cp ${pkgs.writeText "zone" v4Zone} $out
  '';
  v4Path = "/var/lib/nsd/zones/${lib.replaceStrings [ "/" ] [ "-" ] v4Origin}";

  # An address's 32 hex digits, the last first.
  nibbles =
    address:
    lib.reverseList (
      lib.stringToCharacters (
        lib.concatMapStrings (lib.fixedWidthString 4 "0") (
          lib.splitString ":" (lib.network.ipv6.fromString address).address
        )
      )
    );
  v6 = lib.network.ipv6.fromString dn42.ipv6;
  # The digits below the range's prefix name an address in its zone.
  v6Host = (128 - v6.prefixLength) / 4;
  v6Origin = lib.concatStringsSep "." (lib.drop v6Host (nibbles dn42.ipv6)) + ".ip6.arpa.";
  v6Zone =
    start v6Origin + pointers (n: lib.concatStringsSep "." (lib.take v6Host (nibbles "${n.ipv6}/128")));
in
{
  config = lib.mkIf (cfg != null && node.nameserver != null) {
    services.nsd = {
      enable = true;
      interfaces = [
        node.ipv4
        node.ipv6
      ];
      # The addresses sit on the dummy `dn42`, which may come up after NSD.
      ipFreebind = true;
      zones = {
        "${dn42.domain}.".data = zone;
        "${dn42.archive.domain}.".data = archiveZone;
        ${v6Origin}.data = v6Zone;
      };
      extraConfig = ''
        zone:
          name: "${v4Origin}"
          zonefile: "${v4Path}"
      '';
    };

    # After the module's own zones are copied there.
    systemd.services.nsd.preStart = lib.mkAfter ''
      install -m 0444 ${v4ZoneFile} ${lib.escapeShellArg v4Path}
    '';
  };
}
