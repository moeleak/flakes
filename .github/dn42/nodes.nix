# The DN42 nodes (lib/dn42.nix) and the hosts that run them, for
# check-peers.sh:
#
#   nix eval --json --impure --expr 'import ./.github/dn42/nodes.nix (builtins.getFlake (toString ./.))'
#   { "an4": "LoliIsland-VPS-AN4", "as3": "LoliIsland-VPS-AS3" }
flake:
let
  hosts = builtins.filter (host: host != "meta") (builtins.attrNames flake.colmena);
  node = host: flake.nixosConfigurations.${host}.config.my.services.dn42;
in
builtins.listToAttrs (
  builtins.concatMap (
    host:
    if node host == null then
      [ ]
    else
      [
        {
          name = (node host).name;
          value = host;
        }
      ]
  ) hosts
)
