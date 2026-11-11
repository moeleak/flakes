# Strata (github.com/Niko1221/Strata): Qwen3.8-Flash-Next served on http://127.0.0.1:8080, started by hand with
# `systemctl --user start strata` (it holds ~36 GB of RAM and most of the VRAM while it runs).
# Strata itself is installed outside Nix in ~/Projects/Strata by its own setup, run in its flake's dev shell:
#   nix develop --profile .nix/strata-dev -c ./setup.sh ...
# The profile is a GC root that keeps the venv's Python and the engine's CUDA libraries alive.
{
  my.services.strata = {
    # run-iq2_xs.sh without --open, so a start does not open a browser tab
    configFile = "strata-iq2_xs.json";
    model = "Qwen3.8-Flash-Next";
  };
}
