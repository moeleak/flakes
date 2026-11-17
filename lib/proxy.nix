# The Hysteria 2 proxy nodes and who may use them. Read by the sing-box client
# (modules/common/services/sing-box) and by the nodes themselves
# (modules/nixos/services/proxy-node). Node <name> is reachable as <name>.leak.moe.
{
  domain = "leak.moe";

  hysteria = {
    # Without obfuscation, for clients configured with a fixed port.
    port = 8443;
    # Salamander obfuscation; every port in hopPorts is redirected here.
    obfsPort = 8444;
    hopPorts = {
      from = 18443;
      to = 19443;
    };
    hopInterval = "30s";
  };

  # Users besides this flake's own clients. Each one's passwords and
  # configuration token are under `sing-box-users.<user>` in secrets/sing-box.yaml.
  nodes = {
    lax.users = [
      "ada"
      "cjh"
      "dzf"
      "hwl"
      "kyn"
      "mjz"
      "syf"
      "szh"
      "wty"
      "xzh"
      "xzy"
      "zyr"
      "zyw"
    ];
    as3.users = [
      "ada"
      "cjh"
      "dzf"
      "hwl"
      "kyn"
      "mjz"
      "syf"
      "szh"
      "wty"
      "xzh"
      "xzy"
      "zyr"
      "zyw"
    ];
  };
}
