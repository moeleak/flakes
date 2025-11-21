{
  config,
  pkgs,
  lib,
  osConfig,
  pkgs-5a07111,
  inputs,
  ...
}:
{
  imports = [
    inputs.zen-browser.homeModules.beta
  ];

  config = lib.mkMerge [
    (lib.mkIf (osConfig.networking.hostName == "LoliIsland-PC-Nix") {
      programs.plasma = {
        enable = true;
        shortcuts = {
          "services/org.kde.krunner.desktop"._launch = [ "Meta+Space" ];
          "services/org.kde.spectacle.desktop"._launch = [ "Alt+@" ];
        };
      };
    })

    {
      home.username = "moeleak";
      home.homeDirectory = "/home/moeleak";

      programs.zen-browser.enable = true;

      xdg.configFile."ghostty/config".text = ''
        keybind = ctrl+t=new_tab
        cursor-style = bar
        cursor-style-blink = false
        shell-integration = none
      '';

      home.packages = [
        inputs.khanelivim.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.go-musicfox.packages.${pkgs.stdenv.hostPlatform.system}.default

        pkgs.ghostty
        pkgs.fastfetch

        pkgs.devenv
        pkgs.direnv

        # hifi
        pkgs.audacious

        # gaming
        pkgs.moonlight-qt
        pkgs.hmcl

        # cplusplus coding
        pkgs.cmake
        pkgs.ccls
        pkgs.gnumake

        # chat
        pkgs._64gram
        #pkgs.wechat

        # office
        pkgs.libreoffice

        # archives
        pkgs.zip
        pkgs.xz
        pkgs.unzip
        pkgs.p7zip

        # utils
        pkgs.ripgrep
        pkgs.jq
        pkgs.yq-go
        pkgs.eza
        pkgs.fzf
        pkgs.tmux
        pkgs.gitmux
        pkgs.wl-clipboard

        # networking tools
        pkgs.mtr
        pkgs.iperf3
        pkgs.dnsutils
        pkgs.ldns
        pkgs.aria2
        pkgs.socat
        pkgs.nmap
        pkgs.ipcalc

        # misc
        pkgs.cowsay
        pkgs.file
        pkgs.which
        pkgs.tree
        pkgs.gnused
        pkgs.gnutar
        pkgs.gawk
        pkgs.zstd
        pkgs.gnupg

        # nix related
        pkgs.nix-output-monitor

        # productivity
        pkgs.glow

        pkgs.btop
        pkgs.iotop
        pkgs.iftop

        # system call monitoring
        pkgs.strace
        pkgs.ltrace
        pkgs.lsof

        # system tools
        pkgs.sysstat
        pkgs.lm_sensors
        pkgs.ethtool
        pkgs.pciutils
        pkgs.usbutils
      ];

      # basic configuration of git
      programs.git = {
        enable = true;
        lfs.enable = true;
        ignores = [
          ".cache/"
          ".DS_Store"
          ".idea/"
          "*.swp"
          "built-in-stubs.jar"
          "dumb.rdb"
          ".elixir_ls/"
          ".vscode/"
          "npm-debug.log"
          "shell.nix"
          ".direnv"
        ];
        settings = {
          user.name = "MoeLeak";
          user.email = "i@leak.moe";
          alias = {
            st = "status";
          };
          init.defaultBranch = "main";
          push.autoSetupRemote = true;
          pull.rebase = true;
        };
      };

      # starship
      programs.starship = {
        enable = true;
      };

      programs.fish = {
        enable = true;
      };

      home.stateVersion = "25.11";
    }
  ];
}
