{ config, pkgs, ... }:

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
}
