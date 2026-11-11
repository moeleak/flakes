# Command-line tools for every machine with a user environment.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.packages.cli;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  options.my.packages.cli = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      home.packages = [
        pkgs.python3
        pkgs.zellij
        pkgs.ffmpeg
        pkgs.openssh
        pkgs.gnupg
        pkgs.fastfetch
        pkgs.yazi
        pkgs.colmena
        pkgs.gh
        pkgs.lazygit
        pkgs.comma

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
        pkgs.fd
        pkgs.jq
        pkgs.yq-go
        pkgs.eza
        pkgs.bat
        pkgs.fzf
        pkgs.tmux
        pkgs.btop
        pkgs.gitmux

        # lets ssh sessions from kitty find their terminal
        pkgs.kitty.terminfo
      ]
      ++ lib.optionals isLinux [
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
      ];

      programs.password-store.enable = true;
    };
  };
}
