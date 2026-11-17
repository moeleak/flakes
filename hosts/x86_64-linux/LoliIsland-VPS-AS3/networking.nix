# Static addressing, as detected by nixos-infect, except the IPv6 gateway.
{ lib, ... }:
{
  networking = {
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    # The gateway is outside the /32, so name the interface: the route is then
    # installed (and restored on restart) by network-addresses-eth0.
    defaultGateway = {
      address = "193.41.250.250";
      interface = "eth0";
    };
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = "179.255.156.109";
          prefixLength = 32;
        }
      ];
      ipv6.addresses = [
        {
          address = "2605:52c0:1:19ef:be24:11ff:fe47:95ed";
          prefixLength = 64;
        }
        {
          address = "fe80::be24:11ff:fe47:95ed";
          prefixLength = 64;
        }
      ];
      ipv4.routes = [
        {
          address = "193.41.250.250";
          prefixLength = 32;
        }
      ];
    };
  };
  # The IPv6 default route comes from Router Advertisements: the router
  # nixos-infect recorded no longer answers, and a static route to it kept the
  # advertised one out ("ndisc_router_discovery failed to add default route").
  # 2: accept them even when forwarding is on.
  boot.kernel.sysctl."net.ipv6.conf.eth0.accept_ra" = 2;

  services.udev.extraRules = ''
    ATTR{address}=="bc:24:11:47:95:ed", NAME="eth0"
  '';
}
