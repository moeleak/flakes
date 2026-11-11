# LicheePi 4A (RISC-V), cross-compiled on x86_64 and deployed with colmena.
# It is built from its own nixpkgs (the nixos-licheepi4a input), so it keeps
# its own nix settings and only a bare Home Manager profile.
{ inputs, nixpkgs, ... }:
{
  imports = [
    (inputs.nixos-licheepi4a + "/modules/licheepi4a.nix")
    (inputs.nixos-licheepi4a + "/modules/sd-image/sd-image-lp4a.nix")
    ./keyd.nix
    ./packages.nix
    ./services.nix
    ./users.nix
  ];

  networking.hostName = "lp4a";
  nixpkgs.crossSystem.system = "riscv64-linux";

  my = {
    desktop.sway = { };
    system.network = { };

    home = null;
    programs.fish = null;
    system.nix = null;
  };

  nix = {
    settings = {
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
    };
    # `nix shell nixpkgs#...` and <nixpkgs> use the nixpkgs this system is built from
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "/etc/nix/inputs" ];
  };
  environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";

  time.timeZone = "Asia/Shanghai";
  services.timesyncd.enable = true;
  i18n.defaultLocale = "en_US.UTF-8";

  networking = {
    wireless.enable = true;
    interfaces.end0.useDHCP = true;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.moeleak.home.stateVersion = "25.11";
  };
}
