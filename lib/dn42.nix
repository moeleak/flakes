# DN42 (https://dn42.dev), AS4242423507 of MOELEAK-MNT in the registry. Read
# by the nodes on it (modules/nixos/services/dn42) and by the sing-box clients
# (modules/common/services/sing-box), which reach DN42 through them.
let
  proxy = import ./proxy.nix;

  # The VMs on DN42 (lib/vms.nix): nodes like Lab, behind their host's
  # sing-box, which takes their tunnels over VLESS (`viaProxy`). Their
  # addresses follow their `id`s.
  vms = (import ./vms.nix).vms;
  vmNodes =
    builtins.mapAttrs
      (_: vm: {
        inherit (vm) id;
        endpoint = null;
        viaProxy = true;
        vm = vm.host;
        ipv4 = "172.23.122.${toString (64 + vm.id)}";
        ipv6 = "fdd0:3960:d30::${toString vm.id}";
        linkLocal = "fe80::3507:${toString vm.id}";
        inherit (vm.dn42) publicKey;
        nameserver = null;
      })
      (
        builtins.removeAttrs vms (builtins.filter (name: vms.${name}.dn42 == null) (builtins.attrNames vms))
      );
in
{
  asn = 4242423507;
  ipv4 = "172.23.122.64/26";
  ipv6 = "fdd0:3960:d30::/48";

  # The zone that data/dns/moeleak.dn42 in the registry delegates to the
  # nodes; each serves it as its `nameserver` (modules/nixos/services/dn42).
  domain = "moeleak.dn42";

  # The node that takes the mail of `domain`, as mail.<domain>, the zone's MX
  # (modules/nixos/services/dn42/mail.nix), on addresses of its own there,
  # which mail.<domain> names both ways; and its mailboxes there, each with
  # the hash of its password as `dn42-mail/<name>` in secrets/dn42.yaml. The
  # first also takes the mail of postmaster@, hostmaster@, abuse@ and root@.
  # Its mail is signed with DKIM under `dkim.selector`, whose public key, an
  # RSA key in base64 DER, is in the zone; its private key is
  # `dn42-dkim/<selector>` in secrets/dn42.yaml.
  mail = {
    node = "as3";
    # At the top of the ranges, away from the nodes' addresses, which follow
    # their `id`s; 25 as SMTP's port.
    ipv4 = "172.23.122.125";
    ipv6 = "fdd0:3960:d30::25";
    mailboxes = [ "i" ];
    dkim = {
      selector = "mail";
      publicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqvMiSn1I9w7x8UrASJcDKRUaUMSihM9ZLsh7zzRpuh/Q+0swv8H/PTAd8doQ3X7MPiiy26K+XNr82vGFSrQL05CTckRKfAILS8UtVvo94lz0UUnJVjOzphRTcLKiEw3RJEypBa40d41sI5IJPNNcQdb9Mgm0+3HLMDvgojkDM76s5iaxoPYMtWi7B7EJhzkWOt96/FX5HvEqeO78pqxuRzVsG7MujwJn7Lhkrk0KZRWQ57GkivhXQVZ0XpQacZ5B/ys7ufPwpJC377jPLPQoY9ZO0vFHBoLi6zgqr7y3lxuXixISMzdR4KbJhTUJ9td16ArudkKi8/l5tuTu+Qne1QIDAQAB";
    };
  };

  # archive.dn42, a domain of its own beside `domain`, which
  # data/dns/archive.dn42 in the registry delegates to the same nameservers
  # (dns.nix serves it). It names the node `archive.node` by that node's
  # addresses: vm1 (lib/vms.nix), which serves it itself.
  archive = {
    domain = "archive.dn42";
    node = "vm1";
  };

  # What the clients send to the nodes: DN42 itself. Its affiliates in
  # 10.0.0.0/8 stay out, as the campus network uses that range.
  routed = [
    "172.20.0.0/14"
    "fd00::/8"
  ];

  # Everything BIRD takes from the peers (is_valid_network in bird.conf),
  # affiliates included. sing-box on a node leaves it, and the link-local
  # addresses the sessions run on, to the kernel's routes: they stay out of
  # its TUN (route_exclude_address).
  ranges = [
    "172.20.0.0/14"
    "172.31.0.0/16"
    "10.0.0.0/8"
    "fd00::/8"
  ];

  # The nodes. Each has its addresses on a dummy interface, a link-local
  # address on its tunnels, and a WireGuard key (`dn42-wireguard/<name>` in
  # secrets/dn42.yaml) whose public half is `publicKey`. The nodes peer with
  # each other (iBGP), and each with its peers (eBGP) in
  # modules/nixos/services/dn42/peers/<name>/.
  #
  # `endpoint` is where the other nodes reach a node, on the port of their
  # tunnel to it; null for one they don't connect to, which connects to them
  # instead while they wait for it. Two nodes without one have no tunnel
  # between them: the nodes with one reflect their routes to each other
  # (bird.conf's `rr client`). Both ends of the tunnel between two nodes
  # listen on internalPort plus the sum of their `id`s minus 3 (an4 and as3 on
  # 23507, an4 and lp4a on 23508, as3 and lp4a and an4 and lab on 23509, as3
  # and lab and an4 and vm1 on 23510, as3 and vm1 on 23511): the sum is
  # different for each of a node's tunnels, so none share a port.
  #
  # `viaProxy` is for a node that doesn't send its tunnels over plain UDP: its
  # sing-box client takes its tunnels to them over VLESS, each to the proxy
  # node (lib/proxy.nix) it leads to, which hands the packets to its own
  # WireGuard. The others must all have an `endpoint` and be proxy nodes.
  #
  # `nameserver` is its name in `domain` as one of the zone's nameservers,
  # which the registry lists; null for a node that serves no DNS.
  internalPort = 23507;
  nodes = {
    an4 = {
      id = 1;
      endpoint = proxy.nodes.an4.host;
      ipv4 = "172.23.122.65";
      ipv6 = "fdd0:3960:d30::1";
      linkLocal = "fe80::3507:1";
      publicKey = "kbxzD1Hd6kr97/Ab8n1MI49r6LA2g2jARiWcsFNK6DU=";
      nameserver = "ns1";
    };
    as3 = {
      id = 2;
      endpoint = proxy.nodes.as3.host;
      ipv4 = "172.23.122.66";
      ipv6 = "fdd0:3960:d30::2";
      linkLocal = "fe80::3507:2";
      publicKey = "IaF+I0Mk9+U+gF/nS/Yces+PydtLh3wYX1jtK/wBFx8=";
      nameserver = "ns2";
    };
    # The LicheePi 4A (hosts/riscv64-linux/lp4a), in mainland China. It has
    # IPv6, but an4's and as3's names have only IPv4 addresses, so it connects
    # to them over IPv4.
    lp4a = {
      id = 3;
      endpoint = null;
      ipv4 = "172.23.122.67";
      ipv6 = "fdd0:3960:d30::3";
      linkLocal = "fe80::3507:3";
      publicKey = "kI0BouKNTOWe8mV2RwiyBSI/Eh+M1OU8k1nrLmP3PBg=";
      nameserver = null;
    };
    # Lab (hosts/x86_64-linux/biuh-lab), on the campus network. It reaches
    # an4 and as3 over VLESS.
    lab = {
      id = 4;
      endpoint = null;
      viaProxy = true;
      ipv4 = "172.23.122.68";
      ipv6 = "fdd0:3960:d30::4";
      linkLocal = "fe80::3507:4";
      publicKey = "gOmFlPBd4DVqRbF796548Kghe1s48rBKwxiB0sX1Fw4=";
      nameserver = null;
    };
  }
  # And the VMs, whose `vm` is the host they run on.
  // vmNodes;
}
