{
  nixpkgs,
  pkgs,
  ...
}:
{
  imports = [
    ./user-group.nix
    ../../../system/sops.nix
    ../../../programs/sing-box.nix
  ];

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings = {
    auto-optimise-store = true;
    builders-use-substitutes = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  nix.registry.nixpkgs.flake = nixpkgs;
  environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";
  nix.nixPath = [ "/etc/nix/inputs" ];

  environment.systemPackages = with pkgs; [
    openjdk25_headless
    vim
    fastfetch
    mtr
    iperf3
    nmap
    ldns
    socat
    tcpdump
    zip
    xz
    unzip
    p7zip
    zstd
    gnutar
    file
    which
    tree
    gnused
    gawk
    tmux
    docker-compose
  ];

  environment.variables.EDITOR = "nvim";

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      X11Forwarding = true;
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
    openFirewall = true;
  };

  networking = {
    wireless.enable = true;
    firewall.enable = false;

    interfaces.end0 = {
      useDHCP = true;
    };
  };
}
