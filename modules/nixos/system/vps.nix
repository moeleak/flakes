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
      # In the US: cache.nixos.org is fast, a mirror in China is not.
      system.nix.mirrors = [ ];
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

    # The provider (Proxmox) hands out the addresses on a cloud-init drive and
    # changes them from its panel, which needs the guest agent. cloud-init
    # writes them for systemd-networkd on every boot and does nothing else:
    # its other modules would replace the SSH host keys sops decrypts with, and
    # set the users and passwords from the drive.
    services.qemuGuest.enable = true;
    services.cloud-init = {
      enable = true;
      network.enable = true;
      settings = {
        datasource_list = [ "NoCloud" ];
        updates.network.when = [ "boot" ];
        preserve_hostname = true;
        cloud_init_modules = [ ];
        cloud_config_modules = [ ];
        cloud_final_modules = [ ];
      };
    };
    # The drive asks for SLAAC, which cloud-init's networkd output leaves out.
    environment.etc."systemd/network/10-cloud-init-eth0.network.d/ipv6.conf".text = ''
      [Network]
      IPv6AcceptRA=yes
    '';
    # Leave the routes and rules of Tailscale and Docker alone.
    systemd.network.config.networkConfig = {
      ManageForeignRoutes = false;
      ManageForeignRoutingPolicyRules = false;
    };
    # Keep resolv.conf listing `nameservers` for the host and the containers.
    services.resolved.enable = false;
    networking = {
      useDHCP = false;
      usePredictableInterfaceNames = false;
      nameservers = [
        "1.1.1.1"
        "1.0.0.1"
      ];
      firewall.enable = false;
    };

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
