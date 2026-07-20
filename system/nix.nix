{ ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
    "pipe-operators"
  ];

  nix.settings = {
    extra-substituters = [
      "https://devenv.cachix.org"
      "https://cache.leak.moe"
    ];
    extra-trusted-public-keys = [
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "cache.leak.moe-1:mUSixE7LPiarmbyjac1d9qxvEkEl8T6f+hcEIRXLAdM="
    ];
    trusted-users = [
      "root"
      "moeleak"
      "lolimaster"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowAliases = false;
}
