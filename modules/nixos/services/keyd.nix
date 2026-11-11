# keyd key remapping. A host gives its [main] section; the optional "Cmd"
# layer gives macOS-style shortcuts on one modifier (copy/paste, Home/End,
# application switching), and `apps` adds per-application overrides.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.keyd;
  cmd = cfg.cmdLayer;
  user = config.my.user;

  appConf = pkgs.writeText "keyd-app.conf" cfg.apps;

  cmdLayer = ''

    # The Cmd layer, entered from [main] with layer(meta_mac) or overload(meta_mac, ...)
    [meta_mac${lib.optionalString (cmd.inherits != null) ":${cmd.inherits}"}]
    ${cmd.bindings}
    ${lib.concatMapStringsSep "\n" (n: "${toString n} = ${cmd.digits}-${toString n}") (lib.range 1 9)}

    # Copy, paste, cut
    c = C-insert
    v = S-insert
    x = S-delete

    # Beginning and end of the line
    left = home
    right = end

    # As soon as 'tab' is pressed (but not yet released), switch to the 'app_switch_state' overlay
    # Send a 'M-tab' key tap before entering 'app_switch_state'
    tab = swapm(app_switch_state, M-tab)

    # Backtick: switch to the next window in the application group
    ` = A-f6

    # 'app_switch_state' modifier layer; inherits from the 'Meta' modifier layer
    [app_switch_state:M]

    # Tab: switch to the next application
    tab = M-tab
    right = M-tab

    # Backtick: switch to the previous application
    ` = M-S-tab
    left = M-S-tab
  '';
in
{
  options.my.services.keyd = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          # The [main] section, in keyd's own syntax.
          main = lib.mkOption { type = lib.types.lines; };
          # overload_tap_timeout in milliseconds.
          tapTimeout = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
          };
          cmdLayer = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  # Modifier layer to inherit from, e.g. "C" so unbound keys act as Ctrl.
                  inherits = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                  };
                  # What Cmd-1 … Cmd-9 send: "A" for Alt-1 … (tabs), "M" for Meta-1 … (workspaces).
                  digits = lib.mkOption {
                    type = lib.types.str;
                    default = "A";
                  };
                  # Further bindings of the layer.
                  bindings = lib.mkOption {
                    type = lib.types.lines;
                    default = "";
                  };
                };
              }
            );
            default = null;
          };
          # Per-application overrides for keyd-application-mapper.
          apps = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
          };
        };
      }
    );
    default = null;
  };

  config = lib.mkIf (cfg != null) (
    lib.mkMerge [
      {
        services.keyd = {
          enable = true;
          keyboards.default = {
            ids = [ "*" ];
            settings.global = lib.mkIf (cfg.tapTimeout != null) {
              overload_tap_timeout = cfg.tapTimeout;
            };
            extraConfig = ''
              [main]
              ${cfg.main}
            ''
            + lib.optionalString (cmd != null) cmdLayer;
          };
        };
      }

      (lib.mkIf (cfg.apps != null) {
        # keyd calls setgid("keyd") so that the IPC socket is accessible to the keyd group,
        # which needs CAP_SETGID under the module's hardening
        users.groups.keyd = { };
        users.users.${user}.extraGroups = [ "keyd" ];
        systemd.services.keyd.serviceConfig.CapabilityBoundingSet = [ "CAP_SETGID" ];

        home-manager.users.${user} = {
          xdg.configFile."keyd/app.conf".source = appConf;
          systemd.user.services.keyd-application-mapper = {
            Unit = {
              Description = "keyd per-application remapping";
              PartOf = [ "graphical-session.target" ];
              After = [ "graphical-session.target" ];
              # Store files keep a fixed mtime, so the mapper cannot detect changes itself
              X-Restart-Triggers = [ "${appConf}" ];
            };
            Service = {
              ExecStart = "${config.services.keyd.package}/bin/keyd-application-mapper";
              Environment = "KEYD_BIN=${config.services.keyd.package}/bin/keyd";
              Restart = "on-failure";
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      })
    ]
  );
}
