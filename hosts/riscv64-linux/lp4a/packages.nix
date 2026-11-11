{ pkgs, ... }:
{
  programs.starship.enable = true;
  programs.direnv.enable = true;

  environment.systemPackages = with pkgs; [
    # desktop
    firefox
    waypipe
    (prismlauncher.override {
      additionalPrograms = [ ffmpeg ];
      jdks = [ openjdk25_headless ];
    })

    # development
    bear
    nixd
    gnumake
    cmake
    ninja
    pkg-config
    clang-tools
    gdb
    cargo
    rustc
    rust-analyzer
    qemu
    bc
    ncurses.dev

    # graphics and hardware tests
    vkpeak
    vulkan-tools
    mesa-demos
    stress

    # network
    cloudflared
    mtr
    iperf3
    nmap
    ldns
    socat
    tcpdump

    # system
    btop
    yazi
    keyd
    fastfetch
    e2fsprogs
    docker-compose

    # archives
    zip
    xz
    unzip
    p7zip
    zstd
    gnutar

    # shell tools
    file
    which
    tree
    ripgrep
    gnused
    gawk
  ];
}
