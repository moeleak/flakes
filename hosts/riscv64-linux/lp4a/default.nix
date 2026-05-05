{
  config,
  lib,
  nixpkgs,
  pkgs,
  pkgsKernel,
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
    firefox
    btop
    (prismlauncher.override {
      additionalPrograms = [ ffmpeg ];
      jdks = [
        openjdk25_headless
      ];
    })
    cloudflared
    waypipe
    vkpeak
    gnumake
    ncurses.dev
    vulkan-tools
    mesa-demos
    e2fsprogs
    neovim
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

  boot.kernelPackages = lib.mkForce (
    pkgsKernel.linuxPackages_thead.extend (
      _: super: {
        kernel = super.kernel.override (old: {
          kernelPatches = (old.kernelPatches or [ ]) ++ [
            {
              name = "builtin-pstore-for-efi-vars-pstore";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                PSTORE = yes;
              };
            }
          ];
        });
      }
    )
  );

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

  services.cloudflared = {
    enable = true;
    tunnels = {
      "a7c5fdd9-4569-4834-a23c-76f7b676eb8a" = {
        credentialsFile = "/home/moeleak/.cloudflared/a7c5fdd9-4569-4834-a23c-76f7b676eb8a.json";
        default = "http_status:404";
      };
    };
  };

  services.openssh = {
    enable = true;
    ports = [ 2333 ];
    settings = {
      X11Forwarding = true;
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
    openFirewall = true;
  };

  services.glances = {
    enable = true;
    port = 8000;
  };

  sops = {
    secrets."frp-ngb-moeleak-token".sopsFile = ../../../secrets/frp.yaml;
    templates."frp-ngb-moeleak.env" = {
      content = ''
        FRP_TOKEN=${config.sops.placeholder."frp-ngb-moeleak-token"}
      '';
      restartUnits = [ "frp-ngb-moeleak.service" ];
    };
  };

  services.frp = {
    instances."ngb-moeleak" = {
      enable = true;
      role = "client";
      environmentFiles = [
        config.sops.templates."frp-ngb-moeleak.env".path
      ];
      settings = {
        serverAddr = "114.66.6.101";
        serverPort = 7111;
        transport.protocol = "quic";

        auth = {
          method = "token";
          token = "{{ .Envs.FRP_TOKEN }}";
        };

        proxies = [
          {
            name = "tenet";
            type = "tcp";
            localPort = 22;
            remotePort = 22;
          }
        ];
      };
    };
  };

  virtualisation.docker.enable = true;

  networking.networkmanager.enable = true;

  networking = {
    wireless.enable = true;
    firewall.enable = false;

    interfaces.end0 = {
      useDHCP = true;
    };
  };
}
