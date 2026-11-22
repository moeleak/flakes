# OBS Studio, and its plugins through Home Manager's wrapper: on macOS that is
# OBS.app again, with the plugins inside it, among them the voice processing
# filter for echo cancellation and noise suppression
# (github:moeleak/obs-mac-voice-processing).
{
  config,
  lib,
  pkgs,
  inputs,
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
          ++ lib.optionals isDarwin [
            (pkgs.callPackage "${inputs.obs-mac-voice-processing}/package.nix" { })
          ]
          ++ [ (pkgs.callPackage "${inputs.obs-bilibili-stream}/package.nix" { }) ];
      };
    };
  };
}
