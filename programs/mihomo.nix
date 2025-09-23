{ config, pkgs, ... }:

{
  services.mihomo = {
    enable = true;
    configFile = "/home/moeleak/.config/clash/config.yaml";
  };
}
