# DN42 (https://dn42.dev), AS4242423507 of MOELEAK-MNT in the registry. Read
# by the nodes on it (modules/nixos/services/dn42) and by the sing-box clients
# (modules/common/services/sing-box), which reach DN42 through them.
{
  asn = 4242423507;
  ipv4 = "172.23.122.64/26";
  ipv6 = "fdd0:3960:d30::/48";

  # What the clients send to the nodes: DN42 itself. Its affiliates in
  # 10.0.0.0/8 stay out, as the campus network uses that range.
  routed = [
    "172.20.0.0/14"
    "fd00::/8"
  ];

  # The nodes, named as in lib/proxy.nix and reached as <name>.leak.moe. Each
  # has its addresses on a dummy interface, a link-local address on its
  # tunnels, and a WireGuard key (`dn42-wireguard/<name>` in
  # secrets/dn42.yaml) whose public half is `publicKey`. The nodes peer with
  # each other (iBGP) on `internalPort`, and each with its peers (eBGP) in
  # modules/nixos/services/dn42/peers/<name>/.
  internalPort = 23507;
  nodes = {
    lax = {
      ipv4 = "172.23.122.65";
      ipv6 = "fdd0:3960:d30::1";
      linkLocal = "fe80::3507:1";
      publicKey = "kbxzD1Hd6kr97/Ab8n1MI49r6LA2g2jARiWcsFNK6DU=";
    };
    as3 = {
      ipv4 = "172.23.122.66";
      ipv6 = "fdd0:3960:d30::2";
      linkLocal = "fe80::3507:2";
      publicKey = "IaF+I0Mk9+U+gF/nS/Yces+PydtLh3wYX1jtK/wBFx8=";
    };
  };
}
