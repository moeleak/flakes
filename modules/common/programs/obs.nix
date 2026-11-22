# OBS Studio, which nixpkgs builds from the moeleak fork, with an echo
# cancellation filter for macOS ("Echo Cancellation (macOS Voice
# Processing)"). On Linux it comes with its plugins, through Home Manager's
# wrapper; on macOS as OBS.app alone, as the plugins are Linux's and the
# wrapper sets Linux's plugin paths.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.obs;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  options.my.programs.obs = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = lib.mkMerge [
      (lib.mkIf isLinux {
        programs.obs-studio = {
          enable = true;

          package = pkgs.obs-studio.override {
            cudaSupport = (config.my.hardware.nvidia or null) != null;
          };

          plugins = with pkgs.obs-studio-plugins; [
            wlrobs
            obs-backgroundremoval
            obs-pipewire-audio-capture
            obs-gstreamer
            obs-vkcapture
            obs-bilibili-stream
          ];
        };
      })

      (lib.mkIf isDarwin {
        home.packages = [ pkgs.obs-studio ];
      })
    ];
  };
}
