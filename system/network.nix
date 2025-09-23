{ ... }:

{
  # Enable networking
  networking.networkmanager.enable = true;

  networking.proxy.default = "http://127.0.0.1:7890";

  # Or disable the firewall altogether.
  networking.firewall.enable = false;
}
