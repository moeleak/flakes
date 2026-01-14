{ inputs
, pkgs
, ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../../system/boot.nix
    ../../../system/pcscd.nix
    ../../../system/sops.nix
    ./audio.nix
    ./keyd.nix
    ../../../desktop.nix
    ../../../programs/sing-box.nix
    ../../../programs/gnupg.nix
    ../../../programs/openssh.nix
    ../../../programs/rime.nix
    ../../../programs/shell.nix
    ../../../programs/steam.nix
    ../../../programs/tmux.nix
    ../../../programs/xkb.nix
    ../../../zone/fonts.nix
    ../../../zone/locale.nix
  ];

  networking.hostName = "LoliIsland-Laptop-Nix"; # Define your hostname.

  users.users.moeleak = {
    shell = pkgs.fish;
    isNormalUser = true;
    description = "moeleak";
    home = "/home/moeleak";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # make home-manager as a module of nixos
  # so that home-manager configuration will be deployed automatically when executing `nixos-rebuild switch`
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.moeleak = import ../../../home-manager/home.nix;
    extraSpecialArgs = {
      inherit inputs pkgs;
      stdenv.hostPlatform.system = "x86_64-linux";
      pkgs-5a07111 = (
        import inputs.nixpkgs-5a07111 {
          stdenv.hostPlatform.system = "x86_64-linux";
          config.allowUnfree = true;
        }
      );
    };

  };

  programs.nix-ld.enable = true;
  system.stateVersion = "25.05";
}
