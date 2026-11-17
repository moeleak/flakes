# Hysteria 2 node lax.leak.moe.
{
  imports = [
    ./hardware-configuration.nix
  ];

  my = {
    system.vps = { };
    services.proxy-node.name = "lax";
  };

  networking.domain = "lax.leak.moe";

  system.stateVersion = "23.05";
}
