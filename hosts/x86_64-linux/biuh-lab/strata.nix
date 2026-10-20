# Strata (github.com/Niko1221/Strata): Qwen3.8-Flash-Next served on http://127.0.0.1:8080, started by
# hand with `systemctl --user start strata` (it holds ~110 GB of RAM and most of the 2080 Ti while it runs).
# Strata itself is installed outside Nix in ~/Projects/Strata by its own setup, run in its flake's dev shell
# (.nix/devshell.sh: the repo's flake with this host's nixpkgs, since github.com does not answer here):
#   .nix/run-setup-q4.sh
# The model is huihui-ai's abliterated v2 of Unsloth's UD-Q4_K_XL (huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF,
# unsloth-UD-Q4_K_XL-V2; the same tensors and types as Unsloth's file, which setup installs above).  Setup refuses its
# SHA256s, so its files are in Strata-data/models/huihui-v2-UD-Q4_K_XL and its pack was made the way setup makes one:
#   tools/iq_pack.py --gguf <shard 1> --out Strata-data/packs/huihui-v2-ud-q4_k_xl --compat-bf16
# Same speed and MTP draft acceptance as Unsloth's (2026-10-19); strata-unsloth-ud-q4_k_xl.json still runs that one.
# Pictures: the config's "vision" section (mmproj-Qwen3.8-Flash-Next-BF16.gguf in Strata-data/models; strata-vision
# compiled by setup's build_engine, Strata-data/build-vision.py) with "elastic" and "vram_elastic": the encoder starts
# with the first picture (~1.5 GB taken from the expert cache) and stops after 120 s without one, so text keeps its speed.
# The .nix/strata-dev profile is a GC root that keeps the engine's CUDA libraries alive.
#
# The card is shared with ComfyUI (the comfyui-cu130 container): ComfyUI unloads its models after 5 minutes idle
# (comfyui-idle-free below), Strata asks it to before loading (ExecStartPre here, "before_load" in
# strata-huihui-v2-ud-q4_k_xl.json for later loads) and unloads itself after 30 minutes idle ("idle_unload_s").
{ pkgs, lib, ... }:

let
  strataDir = "/home/moeleak/Projects/Strata";
  comfyFree = lib.escapeShellArgs [
    "${pkgs.curl}/bin/curl"
    "-s"
    "-m"
    "10"
    "-X"
    "POST"
    "-H"
    "Content-Type: application/json"
    "-d"
    ''{"unload_models": true}''
    "http://127.0.0.1:8188/free"
  ];
in
{
  # A user unit can raise its memlock limit only up to its user manager's hard limit (8 MiB by default), and the engine
  # mlocks its PLE table (~27 GB of the model file) so the page cache cannot drop it.  As a drop-in, not a whole
  # user@1000.service; the template's X-RestartIfChanged=false is repeated so a switch never restarts the (lingering)
  # manager and everything under it.  A running manager keeps the limit it started with until it restarts (reboot),
  # and each switch re-execs it, which puts that limit back; after a switch, raise it by hand and restart strata:
  #   sudo prlimit --pid "$(systemctl show user@1000 -p MainPID --value)" --memlock=unlimited:unlimited
  systemd.units."user@1000.service" = {
    overrideStrategy = "asDropin";
    text = ''
      [Service]
      LimitMEMLOCK=infinity
      X-RestartIfChanged=false
    '';
  };

  home-manager.users.moeleak = {
    systemd.user.services.strata = {
      Unit = {
        Description = "Strata local LLM server (Qwen3.8-Flash-Next, huihui-ai abliterated v2 UD-Q4_K_XL)";
        ConditionPathExists = "${strataDir}/strata-huihui-v2-ud-q4_k_xl.json";
      };
      Service = {
        WorkingDirectory = strataDir;
        # a ComfyUI that is down must not stop Strata from starting ("-")
        ExecStartPre = "-${comfyFree}";
        # as run-unsloth-ud-q4_k_xl.sh, with the huihui config
        ExecStart = lib.escapeShellArgs [
          "${strataDir}/.venv/bin/python"
          "${strataDir}/serve/server.py"
          "--engine"
          "strata"
          "--config"
          "${strataDir}/strata-huihui-v2-ud-q4_k_xl.json"
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
        # the expert arena (72 GiB) over both sockets' memory: by first touch it all lands on node 0 and the pool
        # workers on node 1 read it across sockets (38.3 tok/s decode); interleaved 40.9 (2026-10-19, 7-10 runs each)
        NUMAPolicy = "interleave";
        NUMAMask = "0-1";
        LimitMEMLOCK = "infinity";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    systemd.user.services.comfyui-idle-free = {
      Unit.Description = "Unload ComfyUI models from VRAM after 5 minutes idle";
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./comfyui-idle-free.py}";
        Environment = "IDLE_S=300";
        Restart = "always";
        RestartSec = 30;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
