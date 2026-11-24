# LicheePi 4A (RISC-V), cross-compiled on x86_64 and deployed with colmena.
# It is built from its own nixpkgs (the nixos-licheepi4a input), so it keeps
# its own nix settings and only a bare Home Manager profile.
{
  inputs,
  lib,
  nixpkgs,
  pkgs,
  ...
}:
{
  imports = [
    (inputs.nixos-licheepi4a + "/modules/licheepi4a.nix")
    (inputs.nixos-licheepi4a + "/modules/sd-image/sd-image-lp4a.nix")
    ./boot.nix
    ./keyd.nix
    ./packages.nix
    ./services.nix
    ./users.nix
  ];

  networking.hostName = "lp4a";
  nixpkgs.crossSystem.system = "riscv64-linux";

  my = {
    # systemd-networkd below instead of NetworkManager.
    system.network = null;
    # A DN42 node (lib/dn42.nix); it connects to an4 and as3, which wait for it.
    services.dn42.name = "lp4a";

    home = null;
    programs.fish = null;
    # The nixvim editor brings language servers (nodejs, boost, ...) to build
    # for riscv64; bare Neovim below instead.
    programs.neovim = null;
    system.nix = null;
  };

  nix = {
    settings = {
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
    };
    # `nix shell nixpkgs#...` and <nixpkgs> use the nixpkgs this system is built from
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "/etc/nix/inputs" ];
  };
  environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";

  # Headless: what licheepi4a.nix adds for a desktop stays out, as it is all
  # cross-compiled. Without graphics, no Mesa; and no fastfetch, which is
  # always built against EFL and with it GTK, GStreamer and PipeWire.
  hardware.graphics.enable = lib.mkForce false;
  nixpkgs.overlays = [ (_: prev: { fastfetch = prev.emptyDirectory; }) ];
  # Neovim without its wrapper, which brings Python and wl-clipboard (Perl,
  # xdg-utils).
  environment.systemPackages = [ pkgs.neovim-unwrapped ];
  environment.variables.EDITOR = "nvim";

  time.timeZone = "Asia/Shanghai";
  services.timesyncd.enable = true;
  i18n.defaultLocale = "en_US.UTF-8";

  networking = {
    useNetworkd = true;
    useDHCP = false;
    # Off, as my.system.network had it.
    firewall.enable = false;
    wireless.enable = true;
  };

  # Wired, or Wi-Fi through wpa_supplicant (networking.wireless), each with
  # DHCP and, though the DN42 node forwards, router advertisements. Either
  # one up is online.
  systemd.network = {
    wait-online.anyInterface = true;
    networks = {
      "30-end0" = {
        matchConfig.Name = "end0";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
      "30-wlan" = {
        matchConfig.Type = "wlan";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.moeleak.home.stateVersion = "25.11";
  };
}
