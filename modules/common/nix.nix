{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.my.system.nix;
in
{
  options.my.system.nix = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = { };
  };

  config = lib.mkIf (cfg != null) {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];

    nix.settings = {
      extra-substituters = [
        "https://devenv.cachix.org"
      ];
      extra-trusted-public-keys = [
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
      trusted-users = [
        "root"
        "moeleak"
        "lolimaster"
      ];
      # If a substituter has a transient outage or connection reset, fall back
      # to building locally instead of hard-failing.
      fallback = true;
    };

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;
    nixpkgs.config.allowAliases = false;
    nixpkgs.overlays = builtins.attrValues inputs.self.overlays;
  };
}
