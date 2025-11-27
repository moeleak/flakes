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
    inputs.plasma-manager.homeModules.plasma-manager
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
        pkgs.clang-tools
        pkgs.clang
        pkgs.llvm
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

      programs.fish = {
        enable = true;
        interactiveShellInit = ''
          set fish_greeting
          set -g fish_color_autosuggestion brblack
          set -g fish_color_cancel --reverse
          set -g fish_color_command 87afd7
          set -g fish_color_comment red
          set -g fish_color_cwd green
          set -g fish_color_cwd_root red
          set -g fish_color_end green
          set -g fish_color_error brred
          set -g fish_color_escape brcyan
          set -g fish_color_history_current --bold
          set -g fish_color_host normal
          set -g fish_color_host_remote yellow
          set -g fish_color_keyword normal
          set -g fish_color_match --background=brblue
          set -g fish_color_normal normal
          set -g fish_color_operator brcyan
          set -g fish_color_option cyan
          set -g fish_color_param cyan
          set -g fish_color_quote yellow
          set -g fish_color_redirection cyan --bold
          set -g fish_color_search_match bryellow --background=brblack
          set -g fish_color_selection white --bold --background=brblack
          set -g fish_color_status red
          set -g fish_color_user brgreen
          set -g fish_color_valid_path --underline

          set -g fish_pager_color_background normal
          set -g fish_pager_color_completion normal
          set -g fish_pager_color_description yellow --italics
          set -g fish_pager_color_prefix normal --bold --underline
          set -g fish_pager_color_progress brwhite --background=cyan
          set -g fish_pager_color_secondary_background normal
          set -g fish_pager_color_secondary_completion normal
          set -g fish_pager_color_secondary_description normal
          set -g fish_pager_color_secondary_prefix normal
          set -g fish_pager_color_selected_background --reverse
          set -g fish_pager_color_selected_completion normal
          set -g fish_pager_color_selected_description normal
          set -g fish_pager_color_selected_prefix normal

          set -g fish_greeting ""
          set -g fish_key_bindings fish_default_key_bindings
        '';

      };
      programs.starship.enable = true;

      home.stateVersion = "25.11";
    }
  ];
}
