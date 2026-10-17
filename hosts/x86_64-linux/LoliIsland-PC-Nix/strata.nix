# Strata (github.com/Niko1221/Strata): Qwen3.8-Flash-Next served on http://127.0.0.1:8080, started by hand with
# `systemctl --user start strata` (it holds ~36 GB of RAM and most of the VRAM while it runs).
# Strata itself is installed outside Nix in ~/Projects/Strata by its own setup, run in its flake's dev shell:
#   nix develop --profile .nix/strata-dev -c ./setup.sh ...
# The profile is a GC root that keeps the venv's Python and the engine's CUDA libraries alive.
{ pkgs, lib, ... }:

let
  strataDir = "/home/moeleak/Projects/Strata";
in
{
  home-manager.users.moeleak = {
    systemd.user.services.strata = {
      Unit = {
        Description = "Strata local LLM server (Qwen3.8-Flash-Next)";
        ConditionPathExists = "${strataDir}/strata-iq2_xs.json";
      };
      Service = {
        WorkingDirectory = strataDir;
        # run-iq2_xs.sh without --open, so a start does not open a browser tab
        ExecStart = lib.escapeShellArgs [
          "${strataDir}/.venv/bin/python"
          "${strataDir}/serve/server.py"
          "--engine"
          "strata"
          "--config"
          "${strataDir}/strata-iq2_xs.json"
          "--port"
          "8080"
        ];
        # libcuda from the driver for the engine; libstdc++ and zlib for the pip wheels in the venv
        Environment = "LD_LIBRARY_PATH=/run/opengl-driver/lib:${
          lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ]
        }";
      };
    };
  };
}
