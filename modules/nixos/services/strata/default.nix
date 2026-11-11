# Strata (github.com/Niko1221/Strata): a local LLM server on http://127.0.0.1:<port>, started by hand with
# `systemctl --user start strata`. Strata itself is installed outside Nix in ~/Projects/Strata by its own setup;
# this only provides the user service. What a host runs and how it was set up is noted in the host's strata.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.strata;
  user = config.my.user;
  dir = "${config.users.users.${user}.home}/Projects/Strata";
  configFile = "${dir}/${cfg.configFile}";

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
  options.my.services.strata = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          # The Strata config to serve, a file name in ~/Projects/Strata.
          configFile = lib.mkOption { type = lib.types.str; };
          # Shown in the unit description.
          model = lib.mkOption { type = lib.types.str; };
          port = lib.mkOption {
            type = lib.types.port;
            default = 8080;
          };
          # Let the engine mlock the model so the page cache cannot drop it.
          memlock = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          # Share the card with a ComfyUI on port 8188: ask it to unload its models before Strata
          # starts, and unload them whenever it has been idle for `idleSeconds`.
          comfyui = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.submodule {
                options.idleSeconds = lib.mkOption {
                  type = lib.types.ints.positive;
                  default = 300;
                };
              }
            );
            default = null;
          };
          # Further [Service] settings of the unit.
          serviceConfig = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
        };
      }
    );
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    # A user unit can raise its memlock limit only up to its user manager's hard limit (8 MiB by default), and the engine
    # mlocks its PLE table (~27 GB of the model file) so the page cache cannot drop it.  As a drop-in, not a whole
    # user@1000.service; the template's X-RestartIfChanged=false is repeated so a switch never restarts the (lingering)
    # manager and everything under it.  A running manager keeps the limit it started with until it restarts (reboot),
    # and each switch re-execs it, which puts that limit back; after a switch, raise it by hand and restart strata:
    #   sudo prlimit --pid "$(systemctl show user@1000 -p MainPID --value)" --memlock=unlimited:unlimited
    systemd.units."user@1000.service" = lib.mkIf cfg.memlock {
      overrideStrategy = "asDropin";
      text = ''
        [Service]
        LimitMEMLOCK=infinity
        X-RestartIfChanged=false
      '';
    };

    home-manager.users.${user}.systemd.user.services = {
      strata = {
        Unit = {
          Description = "Strata local LLM server (${cfg.model})";
          ConditionPathExists = configFile;
        };
        Service = {
          WorkingDirectory = dir;
          ExecStart = lib.escapeShellArgs [
            "${dir}/.venv/bin/python"
            "${dir}/serve/server.py"
            "--engine"
            "strata"
            "--config"
            configFile
            "--port"
            (toString cfg.port)
          ];
          # libcuda from the driver for the engine; libstdc++ and zlib for the pip wheels in the venv
          Environment = "LD_LIBRARY_PATH=/run/opengl-driver/lib:${
            lib.makeLibraryPath [
              pkgs.stdenv.cc.cc.lib
              pkgs.zlib
            ]
          }";
        }
        # a ComfyUI that is down must not stop Strata from starting ("-")
        // lib.optionalAttrs (cfg.comfyui != null) { ExecStartPre = "-${comfyFree}"; }
        // lib.optionalAttrs cfg.memlock { LimitMEMLOCK = "infinity"; }
        // cfg.serviceConfig;
      };

      comfyui-idle-free = lib.mkIf (cfg.comfyui != null) {
        Unit.Description = "Unload ComfyUI models from VRAM after ${toString cfg.comfyui.idleSeconds} s idle";
        Service = {
          ExecStart = "${pkgs.python3}/bin/python3 ${./comfyui-idle-free.py}";
          Environment = "IDLE_S=${toString cfg.comfyui.idleSeconds}";
          Restart = "always";
          RestartSec = 30;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
