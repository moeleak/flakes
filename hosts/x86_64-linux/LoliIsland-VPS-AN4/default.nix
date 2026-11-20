# Proxy node an4 (lax-an4.leak.moe), lax before 2026-11-20.
{
  imports = [
    ./hardware-configuration.nix
  ];

  my = {
    system.vps = { };
    services.proxy-node.name = "an4";
    services.dn42.name = "an4";
  };

  networking.domain = "lax-an4.leak.moe";

  system.stateVersion = "23.05";
}
