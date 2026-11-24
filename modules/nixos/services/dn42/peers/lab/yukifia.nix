# AS4242420091 (YUKIFIA-AS), its cnrouter node: https://dn42.yukifia.moe/.
# It gave its port for us. Lab has no public address, so only Lab connects:
# its endpoint's name resolves to a mainland address (geoip-cn), which
# sing-box sends directly. Its address on the tunnel, as on usrouter's
# (as3/yukifia.nix), fe80::3507.
{
  asn = 4242420091;
  endpoint = "cnrouter.dn42.yukifia.moe:45046";
  publicKey = "ZaKbVOWgy4HnROx5ZuA+6uGHudnS6L7yzSDLjWnCGgE=";
  linkLocal = "fe80::3507";
}
