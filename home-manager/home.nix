{
  config,
  pkgs,
  lib,
  osConfig,
  pkgs-5a07111,
  inputs,
  ...
}:
let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  host = lib.attrByPath [ "networking" "hostName" ] "" osConfig;
in
{
  imports = [
    inputs.zen-browser.homeModules.beta
  ];

  config = lib.mkMerge [
    (lib.optionalAttrs (isLinux && host == "LoliIsland-PC-Nix") {
      programs.plasma = {
        enable = true;
        shortcuts = {
          "services/org.kde.krunner.desktop"._launch = [ "Meta+Space" ];
          "services/org.kde.spectacle.desktop"._launch = [ "Alt+@" ];
        };
      };
    })

    (lib.mkIf isLinux {
      home.username = "moeleak";
      home.homeDirectory = "/home/moeleak";
      programs.zen-browser.enable = true;
      home.packages = [
        pkgs.ghostty
        pkgs.libreoffice
        pkgs._64gram
        pkgs.audacious
        pkgs.moonlight-qt
        pkgs.hmcl
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
    })

    (lib.mkIf isDarwin {
      home.username = "lolimaster";
      home.homeDirectory = "/Users/lolimaster";
      programs = {
        fish.enable = true;
        fish.shellInit = ''
          for p in /run/current-system/sw/bin /etc/profiles/per-user/$USER/bin
            if not contains $p $fish_user_paths
              set -g fish_user_paths $p $fish_user_paths
            end
          end
        '';
      };

    })

    {
      xdg.configFile."ghostty/config".text = ''
        keybind = ctrl+t=new_tab
        cursor-style = bar
        cursor-style-blink = false
        shell-integration = none
      '';

      home.packages = [
        inputs.moevim.packages.${pkgs.stdenv.hostPlatform.system}.default

        pkgs.fastfetch

        pkgs.yazi
        pkgs.devenv
        pkgs.direnv

        # cplusplus coding
        pkgs.cmake
        pkgs.ccls
        pkgs.gnumake

        # chat
        #pkgs.wechat

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
      ];

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

      programs.fish.enable = true;
      programs.starship.enable = true;

      home.stateVersion = "25.11";
    }
  ];
}
