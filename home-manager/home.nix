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

  home.username = if isLinux then "moeleak" else "lolimaster";
  home.homeDirectory = if isLinux then "/home/moeleak" else "/Users/lolimaster";

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.packages = [
    pkgs.ibm-plex
    pkgs.sarasa-gothic
    pkgs.source-han-serif
    pkgs.noto-fonts
    pkgs.noto-fonts-cjk-sans
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts._0xproto

    (import ../programs/neovim.nix { inherit pkgs inputs; })

    pkgs._64gram
    pkgs.thunderbird
    pkgs.ffmpeg
    pkgs.openssh
    pkgs.gnupg
    pkgs.fastfetch
    pkgs.yazi
    pkgs.devenv
    pkgs.direnv
    pkgs.codex
    pkgs.colmena
    pkgs.gh

    pkgs.cargo
    pkgs.rustc
    pkgs.rustfmt

    pkgs.clang-tools
    pkgs.clang
    pkgs.llvm
    pkgs.cmake
    pkgs.ccls
    pkgs.gnumake

    pkgs.zip
    pkgs.xz
    pkgs.unzip
    pkgs.p7zip

    pkgs.iperf3
    pkgs.mtr
    pkgs.aria2
    pkgs.nmap

    pkgs.file
    pkgs.which
    pkgs.tree

    pkgs.ripgrep
    pkgs.jq
    pkgs.yq-go
    pkgs.eza
    pkgs.fzf
    pkgs.tmux
    pkgs.btop
    pkgs.gitmux
  ]
  ++ (lib.optionals isLinux [
    pkgs.wechat
    pkgs.libreoffice
    pkgs.audacious
    pkgs.moonlight-qt
    pkgs.hmcl
    pkgs.wl-clipboard

    pkgs.dnsutils
    pkgs.ldns
    pkgs.socat
    pkgs.ipcalc

    pkgs.strace
    pkgs.ltrace
    pkgs.lsof
    pkgs.iotop
    pkgs.iftop
    pkgs.sysstat
    pkgs.lm_sensors
    pkgs.ethtool
    pkgs.pciutils
    pkgs.usbutils
    pkgs.e2fsprogs

    pkgs.nix-output-monitor
    pkgs.glow

    pkgs.cowsay
    pkgs.gnused
    pkgs.gnutar
    pkgs.gawk
    pkgs.zstd
  ])
  ++ (lib.optionals isDarwin [
    pkgs.apple-sdk
  ]);

  programs.zen-browser.enable = true;

  programs.zen-browser.profiles.main.extensions.packages =
    with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
      ublock-origin
      vimium
    ];

  xdg.dataFile."applications/wechat.desktop".text = lib.optionalString isLinux ''
    [Desktop Entry]
    Type=Application
    Name=Weixin
    Exec=env QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx wechat %U
    Icon=wechat
  '';

  programs.plasma = lib.mkIf isLinux {
    enable = (host == "LoliIsland-PC-Nix" || host == "LoliIsland-Laptop-Nix");
    shortcuts = {
      "services/org.kde.spectacle.desktop"._launch = [ "Alt+@" ];
      "services/org.kde.spectacle.desktop".FullScreenScreenShot = [ "Alt+!" ];
      "services/org.kde.spectacle.desktop".ActiveWindowScreenShot = [ "Alt+#" ];
    }
    // (lib.optionalAttrs (host == "LoliIsland-PC-Nix") {
      "services/org.kde.krunner.desktop"._launch = [ "Meta+Space" ];
    });
    configFile = {
      kwinrc.Wayland = {
        InputMethod = {
          value = "/run/current-system/sw/share/applications/org.fcitx.Fcitx5.desktop";
          shellExpand = true;
        };
        VirtualKeyboardEnabled = true;
      };
    };
  };

  programs.kitty = {
    enable = true;
    font.name = "0xProto Nerd Font Mono";
    font.size = if isLinux then 12 else 18;
    font.package = pkgs.nerd-fonts._0xproto;
    settings.macos_option_as_alt = true;
    themeFile = "Nord";
    keybindings =
      lib.optionalAttrs (host == "LoliIsland-PC-Nix") {
        "ctrl+t" = "new_tab";
        "ctrl+shift+[" = "previous_tab";
        "ctrl+shift+]" = "next_tab";
      }
      // (lib.optionalAttrs (host == "LoliIsland-Laptop-Nix")) {
        "alt+t" = "new_tab";
        "alt+shift+[" = "previous_tab";
        "alt+shift+]" = "next_tab";
      };
  };

  programs.obs-studio = lib.mkIf (isLinux && host == "LoliIsland-PC-Nix") {
    enable = true;

    package = (
      pkgs.obs-studio.override {
        cudaSupport = true;
      }
    );

    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-gstreamer
      obs-vkcapture
      obs-bilibili-stream
    ];
  };

  programs.password-store = {
    enable = true;
  };

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
      sendemail.smtpserver = "smtp.gmail.com";
      sendemail.smtpserverport = 587;
      sendemail.smtpencryption = "tls";
      sendemail.smtpuser = "moeleaking@gmail.com";

      alias = {
        st = "status";
        lg = "log --oneline --graph --all --decorate";
      };
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
    };
  };
  programs.fish = {
    enable = true;

    completions.cargo = builtins.readFile "${pkgs.fish}/share/fish/completions/cargo.fish";

    shellInit = lib.mkIf isDarwin ''
      source /Users/lolimaster/miniconda3/etc/fish/conf.d/conda.fish
      for p in /run/current-system/sw/bin /etc/profiles/per-user/$USER/bin
        if not contains $p $fish_user_paths
          set -g fish_user_paths $p $fish_user_paths
        end
      end
    '';

    interactiveShellInit = ''
      set -g fish_greeting ""

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

      set -g fish_key_bindings fish_default_key_bindings
    '';
  };

  programs.starship.enable = true;
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  home.stateVersion = "25.11";
}
