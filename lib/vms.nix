# The virtual machines, one file each: modules/nixos/services/vms/<host>/<name>.nix
# defines the VM <name> on the host whose networking.hostName is <host>, which
# runs it (modules/nixos/services/vms). Read by that module, by lib/dn42.nix
# (a VM with `dn42` is a node on DN42), and by the host's sing-box client,
# which routes the VMs' traffic.
#
#   # modules/nixos/services/vms/<host>/<name>.nix
#   {
#     id = 5;                  # unique among the VMs and DN42's nodes
#     image = "debian-13";     # a key of modules/nixos/services/vms/images.nix
#     cores = 8;
#     memory = 64;             # GiB
#     disk = 1024;             # GiB, when the disk is created; never shrunk
#     egress = "as3";          # the proxy node (lib/proxy.nix) its proxied traffic takes
#     authorizedKeys = [ "ssh-ed25519 …" ]; # root's, the only login
#     dn42.publicKey = "…";    # left out for a VM off DN42; see lib/dn42.nix
#   }
#
# A VM sits on its host's bridge at `bridge.prefix`.<id>, with the host at
# .1 as its gateway and resolver, and its MAC derived from its id too. Its
# name, as the host's tap vm-<name> and as DN42's interface dn42-<name> on the
# nodes, has at most 10 characters.
let
  dir = ../modules/nixos/services/vms;

  bridge = {
    name = "vmbr0";
    prefix = "192.168.233";
    length = 24;
  };

  defaults = {
    image = "debian-13";
    cores = 1;
    memory = 1;
    disk = 16;
    egress = "an4";
    authorizedKeys = [ ];
    dn42 = null;
  };

  entries = d: builtins.readDir d;
  hosts = builtins.filter (n: (entries dir).${n} == "directory") (builtins.attrNames (entries dir));

  vmsOf =
    host:
    let
      hostDir = dir + "/${host}";
      files = builtins.filter (
        f: (entries hostDir).${f} == "regular" && builtins.match ".*\\.nix" f != null
      ) (builtins.attrNames (entries hostDir));
    in
    map (
      file:
      let
        name = builtins.head (builtins.match "(.*)\\.nix" file);
        vm = defaults // import (hostDir + "/${file}");
      in
      {
        inherit name;
        value = vm // {
          inherit name host;
          address = "${bridge.prefix}.${toString vm.id}";
        };
      }
    ) files;
in
{
  bridge = bridge // {
    address = "${bridge.prefix}.1";
    subnet = "${bridge.prefix}.0/${toString bridge.length}";
  };
  vms = builtins.listToAttrs (builtins.concatMap vmsOf hosts);
}
