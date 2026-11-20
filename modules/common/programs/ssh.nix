# SSH aliases and pinned host keys for the VPS, named as the proxy nodes they
# are (lib/proxy.nix), and Lab's host key on Tailscale, so that any machine
# here can deploy them with colmena (or `ssh as3`, `nixos-rebuild ...
# --target-host as3`).
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.programs.ssh;
  proxy = import ../../../lib/proxy.nix;
  vps = {
    an4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+T4F4mjYL9742+s0fqkKpFEps2XZE16rzM6cO7an0P";
    as3 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN4FQ2QHCk+kZaGUoSgTwgcfbhz3R/q6dlPFyD3WG3zf";
  };
  host = name: proxy.nodes.${name}.host;
in
{
  options.my.programs.ssh = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = { };
  };

  config = lib.mkIf (cfg != null) {
    programs.ssh.knownHosts =
      lib.mapAttrs (name: publicKey: {
        hostNames = [ "[${host name}]:2333" ];
        inherit publicKey;
      }) vps
      // {
        biuh-lab = {
          hostNames = [ "100.64.44.88" ];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHOUTAuzAeGBKS7TMiGtX2NtHBtVZrYqj2+5fRlYMI6R";
        };
      };

    programs.ssh.extraConfig = lib.concatMapStrings (name: ''
      Host ${name}
        HostName ${host name}
        Port 2333
        User root
    '') (lib.attrNames vps);
  };
}
