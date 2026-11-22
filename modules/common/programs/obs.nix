# OBS Studio, which nixpkgs builds from the moeleak fork, with an echo
# cancellation filter for macOS ("Echo Cancellation (macOS Voice
# Processing)"), and its plugins through Home Manager's wrapper: on macOS
# that is OBS.app again, with the plugins inside it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.obs;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  options.my.programs.obs = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      programs.obs-studio = {
        enable = true;

        package = lib.mkIf isLinux (
          pkgs.obs-studio.override {
            cudaSupport = (config.my.hardware.nvidia or null) != null;
          }
        );

        plugins =
          with pkgs.obs-studio-plugins;
          lib.optionals isLinux [
            wlrobs
            obs-backgroundremoval
            obs-pipewire-audio-capture
            obs-gstreamer
            obs-vkcapture
          ]
          ++ [ obs-bilibili-stream ];
      };
    };
  };
}
