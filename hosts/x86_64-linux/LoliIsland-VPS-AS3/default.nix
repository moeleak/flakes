# Proxy node as3.leak.moe.
{
  imports = [
    ./hardware-configuration.nix
  ];

  my = {
    system.vps = { };
    services.proxy-node.name = "as3";
    services.dn42.name = "as3";
  };

  networking.domain = "as3.leak.moe";

  system.stateVersion = "23.05";
}
