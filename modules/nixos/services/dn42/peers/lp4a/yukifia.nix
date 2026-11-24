# AS4242420091 (YUKIFIA-AS), its cnrouter node: https://dn42.yukifia.moe/.
# It gave its port for us and its address on the tunnel, fe80::91. lp4a has
# no public IPv4 address, so only lp4a connects, from its home network: Lab
# had this peering first, but its campus network drops WireGuard's
# handshake responses. lp4a took over Lab's WireGuard key then (Lab got a new
# one), and takes Lab's address on the tunnel, so cnrouter kept its side.
{
  asn = 4242420091;
  endpoint = "cnrouter.dn42.yukifia.moe:45046";
  publicKey = "ZaKbVOWgy4HnROx5ZuA+6uGHudnS6L7yzSDLjWnCGgE=";
  linkLocal = "fe80::91";
  localLinkLocal = "fe80::3507:4";
}
