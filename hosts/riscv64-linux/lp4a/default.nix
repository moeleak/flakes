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
    vulkan-tools
    mesa-demos
    e2fsprogs
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

  programs.sway.enable = true;

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
        user = "greeter";
      };
    };
  };

  services.minecraft-server = {
    enable = true;
    package = pkgs.papermc;
    eula = true;
    declarative = true;
    serverProperties = {
      server-port = 25565;
      difficulty = 3;
      gamemode = 0;
      max-players = 20;
      motd = "Minecraft Server on RISC-V";
      white-list = false;
      allow-cheats = false;
    };
    jvmOpts = "-Xms4096M -Xmx4096M";
  };

  services.openssh = {
    enable = true;
    settings = {
      X11Forwarding = true;
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
    openFirewall = true;
  };

  networking.networkmanager.enable = true;

  networking = {
    wireless.enable = true;
    firewall.enable = false;

    interfaces.end0 = {
      useDHCP = true;
    };
  };
}
