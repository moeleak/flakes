# Hysteria 2 node as3.leak.moe.
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
  ];

  my = {
    system.vps = { };
    services.proxy-node.name = "as3";
  };

  networking.domain = "as3.leak.moe";

  system.stateVersion = "23.05";
}
