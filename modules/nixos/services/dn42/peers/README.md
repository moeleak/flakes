# Peering with MoeLeak (AS4242423507)

## Nodes

Both are in Los Angeles, and both names resolve to IPv4 and IPv6.

| Node | Endpoint | WireGuard public key | Link-local | DN42 addresses |
| --- | --- | --- | --- | --- |
| `an4` | `lax-an4.leak.moe` | `kbxzD1Hd6kr97/Ab8n1MI49r6LA2g2jARiWcsFNK6DU=` | `fe80::3507:1` | 172.23.122.65, fdd0:3960:d30::1 |
| `as3` | `lax-as3.leak.moe` | `IaF+I0Mk9+U+gF/nS/Yces+PydtLh3wYX1jtK/wBFx8=` | `fe80::3507:2` | 172.23.122.66, fdd0:3960:d30::2 |

- The port is 2 followed by the last four digits of your ASN:
  20207 for AS4242420207.
- WireGuard's MTU is 1420.
- My BGP is MP-BGP over the link-local addresses with Extended Next Hop,
  which carries both IPv4 and IPv6.

## Peering

Add `modules/nixos/services/dn42/peers/<node>/<name>.nix`, as
`as3/example.nix`.

```nix
# AS4242420000 (EXAMPLE-AS), its lax1 node: https://example.dn42/peering.
{
  asn = 4242420000;
  # Where we reach you; leave it out if only you connect to us.
  endpoint = "lax1.example.com:23507";
  publicKey = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789+/AbCdE=";
  # Yours, on this tunnel.
  linkLocal = "fe80::1234";
}
```
- A WireGuard preshared key does not go in the pull request: ask me for one.
