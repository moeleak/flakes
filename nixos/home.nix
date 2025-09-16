{ config, pkgs, inputs, ... }:
let
  system = "x86_64-linux";
in
{
  # TODO please change the username & home directory to your own
  home.username = "moeleak";
  home.homeDirectory = "/home/moeleak";

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  # set cursor size and dpi for 4k monitor
  # xresources.properties = {
  #   "Xcursor.size" = 16;
  #   "Xft.dpi" = 172;
  # };

  # Packages that should be installed to the user profile.

  imports = [
    inputs.zen-browser.homeModules.beta
  ];
  programs.zen-browser.enable = true;



  home.packages =  [
    # here is some command line tools I use frequently
    # feel free to add your own or remove some of them
    inputs.nvix.packages.${system}.default
    inputs.go-musicfox.packages.${system}.default

    pkgs.ghostty
    pkgs.fastfetch
    pkgs.audacious

    # gaming
    pkgs.moonlight-qt

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
    pkgs.wl-clipboard # command line clipboard utilities for wayland

    # networking tools
    pkgs.mtr # A network diagnostic tool
    pkgs.iperf3
    pkgs.dnsutils  # `dig` + `nslookup`
    pkgs.ldns # replacement of `dig`, it provide the command `drill`
    pkgs.aria2 # A lightweight multi-protocol & multi-source command-line download utility
    pkgs.socat # replacement of openbsd-netcat
    pkgs.nmap # A utility for network discovery and security auditing
    pkgs.ipcalc  # it is a calculator for the IPv4/v6 addresses

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

    pkgs.btop  # replacement of htop/nmon
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
    userName = "MoeLeak";
    userEmail = "i@leak.moe";
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
