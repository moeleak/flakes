{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.obs;
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

        package = pkgs.obs-studio.override {
          cudaSupport = config.my.hardware.nvidia != null;
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
    };
  };
}
