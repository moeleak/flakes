{ config, pkgs, ... }:

let
  # Restore default modifier behavior while Counter-Strike 2 is focused
  appConf = pkgs.writeText "keyd-app.conf" ''
    [cs2]
    control = layer(control)
    leftmeta = layer(meta)
  '';
in
{
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        #settings = {
        #  main = {
        #    # meta = "overload(control, esc)";  # For pixelbook go
        #    # capslock = "overload(control, esc)";
        #    control = "overload(control, esc)";
        #    #leftmeta = "overload(alt, meta)";
        #  };
        #};
        settings.global.overload_tap_timeout = 200;
        extraConfig = ''
          [main]

          # Use the 'leftmeta' key as the new "Cmd" key, activating the 'meta_mac' layer
          control = overload(control, esc);
          leftmeta = layer(meta_mac)

          # Optional: Ensure 'leftalt' retains its default behavior (usually not necessary)
          # leftalt = leftalt

          # The 'meta_mac' modifier layer; inherits from the 'Ctrl' modifier layer
          [meta_mac:C]
          space = M-space

          # Switch directly to an open tab (e.g., Firefox, VS Code)
          1 = A-1
          2 = A-2
          3 = A-3
          4 = A-4
          5 = A-5
          6 = A-6
          7 = A-7
          8 = A-8
          9 = A-9

          # Copy
          c = C-insert
          # Paste
          v = S-insert
          # Cut
          x = S-delete

          # Move cursor to the beginning of the line
          left = home
          # Move cursor to the end of the line
          right = end

          # As soon as 'tab' is pressed (but not yet released), switch to the 'app_switch_state' overlay
          # Send a 'M-tab' key tap before entering 'app_switch_state'
          tab = swapm(app_switch_state, M-tab)

          # Meta-Backtick: Switch to the next window in the application group
          # Default binding for 'cycle-group' in GNOME
          ` = A-f6

          # 'app_switch_state' modifier layer; inherits from the 'Meta' modifier layer
          [app_switch_state:M]

          # Meta-Tab: Switch to the next application
          tab = M-tab
          right = M-tab

          # Meta-Backtick: Switch to the previous application
          ` = M-S-tab
          left = M-S-tab
        '';
      };
    };
  };

  # keyd calls setgid("keyd") so that the IPC socket is accessible to the keyd group,
  # which needs CAP_SETGID under the module's hardening
  users.groups.keyd = { };
  users.users.moeleak.extraGroups = [ "keyd" ];
  systemd.services.keyd.serviceConfig.CapabilityBoundingSet = [ "CAP_SETGID" ];

  home-manager.users.moeleak = {
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
}
