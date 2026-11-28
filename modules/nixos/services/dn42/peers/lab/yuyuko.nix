# AS4242421117 (Yuyuko-Network), its cn04 node: https://dn42.yuyuko.com. It
# gave its port for us and its address on the tunnel, fe80::1117, and expects
# fe80::3507 on our side: it connects there, and resets a session from any
# other address. Its endpoint, in Shenzhen on China Telecom, is in mainland
# China, 16 ms away: sing-box on Lab sends the tunnel directly (geoip-cn).
{
  asn = 4242421117;
  endpoint = "cn04-338de60b.dn42.yuyuko.com:21117";
  publicKey = "9Dc+k0Lh5LV62fF+z75sHX1AUxV5v6Y5SIaqHtKiOHs=";
  linkLocal = "fe80::1117";
  localLinkLocal = "fe80::3507";
  # Asia-E: elsewhere, Shenzhen is farther than Los Angeles, as burble.dn42,
  # 2 ms from as3, was 346 ms from Lab through cn04.
  regions = [ 52 ];
}
