# A small rented VM (QEMU, installed with nixos-infect), administered as root.
# It is too small to evaluate or build its own system, so it is deployed from
# another machine with Lab as the builder; see the README.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.system.vps;
in
{
  options.my.system.vps = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    my = {
      # No human user: secrets are decrypted with the host key.
      home = lib.mkDefault null;
      sops.hostKey = true;
      services.sing-box = lib.mkDefault null;
      programs.neovim = lib.mkDefault null;
    };

    time.timeZone = "Asia/Shanghai";

    boot = {
      tmp.cleanOnBoot = true;
      kernelModules = [ "tcp_bbr" ];
      kernel.sysctl = {
        "net.core.default_qdisc" = "cake";
        "net.ipv4.tcp_congestion_control" = "bbr";
      };
    };
    zramSwap.enable = true;

    networking.firewall.enable = false;

    services.openssh = {
      enable = true;
      ports = [ 2333 ];
    };
    users.users.root.openssh.authorizedKeys.keys = [
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAICAigxIb0V91FTl4uHYySI6UuXl5Pbwq7x5+FoeErwR7AAAABHNzaDo= ssh:"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMz+2frjnWmRB86/XlWOaPLxSWnQRIAwf7x83v8xTaHw i@leak.moe"
    ];

    services.tailscale.enable = true;
    virtualisation.docker.enable = true;

    environment.systemPackages = with pkgs; [
      btop
      git
      microfetch
      vim
    ];

    # The system comes from the flake; keep the disk small.
    nix = {
      channel.enable = false;
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
      settings.auto-optimise-store = true;
    };
    documentation.enable = false;
  };
}
