# What is wrong with DN42 peer files, for check-peers.sh. `files` is a JSON
# list of their paths below modules/nixos/services/dn42/peers, as
# "as3/sironeko.nix". The result:
#
#   {
#     errors = [ "as3/sironeko.nix: has no `publicKey`" ];
#     peers = [ { file = "as3/sironeko.nix"; node = "as3"; asn = 4242421573; endpoint = "…"; } ];
#   }
#
# with in `peers` the files without errors. check-peers.sh checks the rest on
# the evaluated node: that no two of its tunnels listen on one port, and (the
# module's assertions) the length of the interface's name.
{ files }:
let
  dn42 = import ../../lib/dn42.nix;
  peersDir = ../../modules/nixos/services/dn42/peers;

  # What modules/nixos/services/dn42 reads from a peer file.
  keys = [
    "asn"
    "endpoint"
    "publicKey"
    "linkLocal"
    "port"
    "localLinkLocal"
    "presharedKey"
    "regions"
  ];
  required = [
    "asn"
    "publicKey"
    "linkLocal"
  ];

  optional = cond: message: if cond then [ message ] else [ ];
  matches = re: value: builtins.isString value && builtins.match re value != null;
  isPort = value: builtins.isInt value && value > 0 && value < 65536;
  # As BIRD and WireGuard print them, the interface ID in at most four groups.
  isLinkLocal = matches "fe80::[0-9a-f]{1,4}(:[0-9a-f]{1,4}){0,3}";
  # 32 bytes in base64.
  isKey = matches "[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=";
  isEndpoint =
    value:
    let
      parts =
        if builtins.isString value then
          builtins.match "(\\[[0-9a-f:]+]|[A-Za-z0-9.-]+):([1-9][0-9]{0,4})" value
        else
          null;
    in
    parts != null && isPort (builtins.fromJSON (builtins.elemAt parts 1));

  # The peers with a preshared key, the keys below `dn42-wireguard-psk` in
  # secrets/dn42.yaml: sops leaves the names in the clear.
  pskNames =
    let
      lines = builtins.filter builtins.isString (
        builtins.split "\n" (builtins.readFile ../../secrets/dn42.yaml)
      );
      step =
        state: line:
        let
          name = builtins.match " +([a-z0-9-]+):.*" line;
        in
        if builtins.match "[^ ].*" line != null then
          state // { inside = line == "dn42-wireguard-psk:"; }
        else if state.inside && name != null then
          state // { names = state.names ++ name; }
        else
          state;
    in
    (builtins.foldl' step {
      inside = false;
      names = [ ];
    } lines).names;

  problems =
    file:
    let
      parts = builtins.match "([^/]+)/([^/]+)\\.nix" file;
      node = builtins.elemAt parts 0;
      name = builtins.elemAt parts 1;
      ours = dn42.nodes.${node};
      peer = import (peersDir + "/${file}");
      has = key: peer ? ${key};
    in
    if parts == null then
      [ "is not <node>/<name>.nix" ]
    else if !(dn42.nodes ? ${node}) then
      [
        "${node} is not one of our nodes: ${builtins.concatStringsSep ", " (builtins.attrNames dn42.nodes)}"
      ]
    else if builtins.match "[a-z0-9][a-z0-9-]{0,9}" name == null then
      [
        "the name ${name} must be at most 10 lowercase letters, digits and -: it names the interface dn42-${name}"
      ]
    else if !builtins.isAttrs peer then
      [ "is not an attribute set" ]
    else
      map (key: "has no `${key}`") (builtins.filter (key: !has key) required)
      ++ map (key: "has `${key}`, which is none of ${builtins.concatStringsSep ", " keys}") (
        builtins.filter (key: !builtins.elem key keys) (builtins.attrNames peer)
      )
      ++ optional (
        has "asn" && !(builtins.isInt peer.asn && peer.asn > 0 && peer.asn < 4294967296)
      ) "`asn` is not an AS number"
      ++ optional ((peer.asn or null) == dn42.asn) "`asn` is ours"
      ++ optional (has "publicKey" && !isKey peer.publicKey) "`publicKey` is not a WireGuard public key"
      ++ optional (
        has "linkLocal" && !isLinkLocal peer.linkLocal
      ) "`linkLocal` is not a link-local address, as fe80::1234 (in lowercase)"
      ++ optional (
        (peer.linkLocal or null) == (peer.localLinkLocal or ours.linkLocal)
      ) "`linkLocal` is our own address on the tunnel"
      ++ optional (
        has "endpoint" && !isEndpoint peer.endpoint
      ) "`endpoint` is not \"host:port\" (\"[address]:port\" for IPv6)"
      ++ optional (
        !has "endpoint" && (ours.endpoint or "") == null
      ) "${node} is behind NAT, so it needs your `endpoint`"
      ++ optional (has "port" && !isPort peer.port) "`port` is not a port"
      ++ optional (
        has "localLinkLocal" && !isLinkLocal peer.localLinkLocal
      ) "`localLinkLocal` is not a link-local address, as fe80::1234 (in lowercase)"
      ++ optional (
        has "presharedKey" && !builtins.isBool peer.presharedKey
      ) "`presharedKey` is not true or false"
      # DN42's region communities, (64511, 41) to (64511, 53).
      ++ optional (
        has "regions"
        && !(
          builtins.isList peer.regions
          && builtins.all (region: builtins.isInt region && region >= 41 && region <= 53) peer.regions
        )
      ) "`regions` is not a list of DN42 regions, 41 to 53"
      ++
        optional ((peer.presharedKey or false) == true && !builtins.elem name pskNames)
          "`presharedKey` is set, but secrets/dn42.yaml has no dn42-wireguard-psk/${name}: leave it out and send the key privately";

  checked = map (file: {
    inherit file;
    problems = problems file;
  }) (builtins.fromJSON files);
  good = builtins.filter (c: c.problems == [ ]) checked;
in
{
  errors = builtins.concatMap (c: map (problem: "${c.file}: ${problem}") c.problems) checked;
  peers = map (
    c:
    let
      peer = import (peersDir + "/${c.file}");
    in
    {
      inherit (c) file;
      node = builtins.head (builtins.match "([^/]+)/.*" c.file);
      inherit (peer) asn;
      endpoint = peer.endpoint or null;
    }
  ) good;
}
