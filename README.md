# Yubikey

Before rebuilding you need to export your age key to a specific folder.

```
$ nix shell nixpkgs#age-plugin-yubikey
$ age-plugin-yubikey --identity --slot 1 > $HOME/.config/sops/age/keys.txt
```

# Proxy

The `proxy` selector uses Hysteria 2 on UDP 8443: `hysteria-lax` is the
default and `hysteria-as3` is the alternate. VLESS outbounds are retired.
The existing Lab relay and `auto` routing remain available.
UDP 8443 avoids the UDP 443 filtering observed on the current client network.

Node addresses, separate passwords, and TLS public-key pins are encrypted in
`secrets/sing-box.yaml`. Each VPS stores its Hysteria configuration in
`/etc/nixos/hysteria.nix`, its password in
`/etc/nixos/secrets/hysteria-password`, and its ECDSA certificate/key under
`/var/lib/sing-box/hysteria/`. Clients authenticate the pinned key; replacing a
server key requires updating that node's encrypted `sing-box-hysteria-*-pin`.
The servers retain their existing VLESS listeners for other clients.
