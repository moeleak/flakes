# The proxy nodes and who may use them. Read by the sing-box client
# (modules/common/services/sing-box) and by the nodes themselves
# (modules/nixos/services/proxy-node). Each node is reached by its `host`, so
# changing its address only takes a DNS update.
{
  domain = "leak.moe";

  # VLESS with XTLS Vision over TLS, with a Let's Encrypt certificate that
  # sing-box obtains itself.
  vless = {
    port = 8443;
    flow = "xtls-rprx-vision";
  };

  # The Shadowsocks 2022 relay on Lab (biuh-lab), reachable only from its
  # campus network; password `sing-box-lab-password`. The flake's clients use it
  # as `lab`, and so do the profiles with &lab=true.
  lab = {
    address = "10.90.0.3";
    port = 8388;
    directPort = 8389;
  };

  # Every user downloads one profile from https://<host>/query?token=<token>,
  # with all the nodes below that list them. One node serves it; DNS for
  # `host` must point there.
  profiles = {
    host = "config.leak.moe";
    node = "an4";
  };

  # Each node's name, and its users besides this flake's own clients; a user's
  # VLESS UUID and profile token are under `sing-box-users.<user>` in
  # secrets/sing-box.yaml. `formerHosts` are the names a node went by until
  # 2026-11-20 (an4 was lax): profiles downloaded before still use them, so
  # its certificate covers them too until those profiles are gone.
  nodes = {
    an4 = {
      host = "lax-an4.leak.moe";
      formerHosts = [ "lax.leak.moe" ];
      users = [
        "ada"
        "cjh"
        "dzf"
        "hwl"
        "kyn"
        "lxz"
        "mjz"
        "syf"
        "szh"
        "wgr"
        "wty"
        "xzh"
        "xzy"
        "zyr"
        "zyw"
      ];
    };
    as3 = {
      host = "lax-as3.leak.moe";
      formerHosts = [ "as3.leak.moe" ];
      users = [
        "ada"
        "cjh"
        "dzf"
        "hwl"
        "kyn"
        "lxz"
        "mjz"
        "syf"
        "szh"
        "wgr"
        "wty"
        "xzh"
        "xzy"
        "zyr"
        "zyw"
      ];
    };
  };
}
