#!/usr/bin/env bash
# Checks the DN42 peers a pull request adds, changes or removes, for
# .github/workflows/dn42-peers.yml; see modules/nixos/services/dn42/peers. Run
# it from the repository's root, on the pull request's merge commit (HEAD^1
# being the branch it merges into) or with BASE set to the commit to compare
# with.
#
# It changes nothing but peer files. Each changed file has the fields
# check-peers.nix wants, an ASN in the DN42 registry, and nixfmt's format; each
# node it is for still evaluates, its modules' assertions included, no two of
# its tunnels listen on one port, and BIRD parses its configuration. The bot's private repository (the input
# apple-music-bot), which as3 builds, is stood in for, since nothing here is
# built from it.
set -euo pipefail

base=${BASE:-HEAD^1}
dir=modules/nixos/services/dn42/peers
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
status=0
error() {
  echo "::error::$*"
  status=1
}
# As GitHub Actions groups output, and plainly elsewhere.
group() { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }

all=$(git diff --name-only --no-renames "$base" HEAD)
others=$(grep -v -E "^$dir/[^/]+/[^/]+\.nix\$" <<<"$all" || true)
if [ -n "$others" ]; then
  error "Only peer files ($dir/<node>/<name>.nix) may change, not: $(tr '\n' ' ' <<<"$others")"
  exit 1
fi
changed=$(git diff --name-only --no-renames --diff-filter=d "$base" HEAD | sed "s|^$dir/||")
nodes=$(sed "s|^$dir/||; s|/.*||" <<<"$all" | sort -u)

group "Fields"
files=$(jq -R . <<<"$changed" | jq -cs 'map(select(. != ""))')
result=$(nix-instantiate --eval --strict --json .github/dn42/check-peers.nix --argstr files "$files")
mapfile -t errors < <(jq -r '.errors[]' <<<"$result")
for e in "${errors[@]}"; do error "$dir/$e"; done
endgroup

group "Registry"
{
  echo "| Peer | ASN | Name | Maintainer | Endpoint |"
  echo "| --- | --- | --- | --- | --- |"
} >>"$summary"
while read -r peer; do
  file=$(jq -r .file <<<"$peer")
  asn=$(jq -r .asn <<<"$peer")
  endpoint=$(jq -r '.endpoint // "(they connect to us)"' <<<"$peer")
  # The DN42 registry's objects, from https://explorer.burble.com.
  if object=$(curl -fsS --retry 3 "https://explorer.burble.com/api/registry/aut-num/AS$asn"); then
    attribute() { jq -r --arg k "$1" '.[].Attributes[] | select(.[0] == $k) | .[1]' <<<"$object" | head -1 | sed -E 's/^\[([^]]*)\].*/\1/'; }
    name=$(attribute as-name)
    mnt=$(attribute mnt-by)
    echo "$file: AS$asn ${name:-} (${mnt:-})"
    echo "| $file | AS$asn | ${name:-} | ${mnt:-} | $endpoint |" >>"$summary"
  else
    error "$dir/$file: AS$asn is not in the DN42 registry"
  fi
done < <(jq -c '.peers[]' <<<"$result")
endgroup

if [ -n "$changed" ]; then
  group "Format"
  mapfile -t paths <<<"$changed"
  nix run --inputs-from . nixpkgs#nixfmt -- --check "${paths[@]/#/$dir/}" ||
    error "Format the peer files with nixfmt (nix run nixpkgs#nixfmt -- <file>)"
  endgroup
fi

[ "$status" = 0 ] || exit 1

hosts=$(nix eval --json --impure --expr 'import ./.github/dn42/nodes.nix (builtins.getFlake (toString ./.))')
stub=(--override-input apple-music-bot "path:$PWD/.github/dn42")
for node in $nodes; do
  host=$(jq -r --arg node "$node" '.[$node] // empty' <<<"$hosts")
  if [ -z "$host" ]; then
    error "No host runs the node $node"
    continue
  fi
  group "$node ($host)"
  system=".#nixosConfigurations.$host.config"
  nix eval --raw "${stub[@]}" "$system.system.build.toplevel.drvPath" ||
    error "$host does not evaluate with these peers"
  # shellcheck disable=SC2016 # Nix, not shell
  ports=$(nix eval --json "${stub[@]}" "$system.systemd.network.netdevs" --apply '
    netdevs: map (netdev: netdev.wireguardConfig.ListenPort)
      (builtins.filter (netdev: netdev ? wireguardConfig.ListenPort) (builtins.attrValues netdevs))')
  for port in $(jq -r 'group_by(.) | map(select(length > 1) | .[0]) | .[]' <<<"$ports"); do
    error "Two of $node's tunnels listen on port $port: set \`port\` (ours) in the new peer's file"
  done
  nix build --no-link "${stub[@]}" "$system.environment.etc.\"bird/bird.conf\".source" ||
    error "BIRD does not take $node's configuration with these peers"
  endgroup
done

exit "$status"
