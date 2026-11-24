# A headless DN42 node now: the desktop, development and graphics tools are
# gone, as everything here is cross-compiled for riscv64 on x86_64 and they
# made it thousands of builds.
{ pkgs, ... }:
{
  programs.starship.enable = true;
  programs.direnv.enable = true;

  environment.systemPackages = with pkgs; [
    # network
    mtr
    iperf3
    nmap
    ldns
    socat
    tcpdump
    wireguard-tools

    # system
    btop
    keyd
    e2fsprogs

    # archives
    zip
    xz
    unzip
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
