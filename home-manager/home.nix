{
  config,
  pkgs,
  pkgs-5a07111,
  inputs,
  ...
}:
{
  home.username = "moeleak";
  home.homeDirectory = "/home/moeleak";

  imports = [
    inputs.zen-browser.homeModules.beta
  ];
  programs.zen-browser.enable = true;

  xdg.configFile."ghostty/config".text = ''
    keybind = ctrl+t=new_tab
    cursor-style = bar
    cursor-style-blink = false
    shell-integration = none
  '';

  home.packages = [
    inputs.khanelivim.packages.${pkgs.system}.default
    inputs.go-musicfox.packages.${pkgs.system}.default

    pkgs-5a07111.ghostty
    pkgs.fastfetch

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
    pkgs.ripgrep # recursively searches directories for a regex pattern
    pkgs.jq # A lightweight and flexible command-line JSON processor
    pkgs.yq-go # yaml processor https://github.com/mikefarah/yq
    pkgs.eza # A modern replacement for ‘ls’
    pkgs.fzf # A command-line fuzzy finder
    pkgs.tmux
    pkgs.gitmux
    pkgs.wl-clipboard # command line clipboard utilities for wayland

    # networking tools
    pkgs.mtr # A network diagnostic tool
    pkgs.iperf3
    pkgs.dnsutils # `dig` + `nslookup`
    pkgs.ldns # replacement of `dig`, it provide the command `drill`
    pkgs.aria2 # A lightweight multi-protocol & multi-source command-line download utility
    pkgs.socat # replacement of openbsd-netcat
    pkgs.nmap # A utility for network discovery and security auditing
    pkgs.ipcalc # it is a calculator for the IPv4/v6 addresses

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
    #
    # it provides the command `nom` works just like `nix`
    # with more details log output
    pkgs.nix-output-monitor

    # productivity
    pkgs.glow # markdown previewer in terminal

    pkgs.btop # replacement of htop/nmon
    pkgs.iotop # io monitoring
    pkgs.iftop # network monitoring

    # system call monitoring
    pkgs.strace # system call monitoring
    pkgs.ltrace # library call monitoring
    pkgs.lsof # list open files

    # system tools
    pkgs.sysstat
    pkgs.lm_sensors # for `sensors` command
    pkgs.ethtool
    pkgs.pciutils # lspci
    pkgs.usbutils # lsusb
  ];

  # basic configuration of git, please change to your own
  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "MoeLeak";
    userEmail = "i@leak.moe";
    extraConfig = {
      init.defaultBranch = "main";
    };
  };

  # starship - an customizable prompt for any shell
  programs.starship = {
    enable = true;
  };

  programs.fish = {
    enable = true;
  };

  # This value determines the home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update home Manager without changing this value. See
  # the home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.11";
}
