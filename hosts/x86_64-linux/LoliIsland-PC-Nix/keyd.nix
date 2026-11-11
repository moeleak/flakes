{
  my.services.keyd = {
    tapTimeout = 200;
    # Use the 'leftmeta' key as the new "Cmd" key, activating the 'meta_mac' layer
    main = ''
      control = overload(control, esc);
      leftmeta = layer(meta_mac)
    '';
    cmdLayer = {
      # unbound keys act as Ctrl
      inherits = "C";
      # Cmd-1 … Cmd-9 switch directly to an open tab (e.g., Firefox, VS Code)
      digits = "A";
      bindings = "space = M-space";
    };
    # Application-specific overrides for the Cmd layer and game modifiers
    apps = ''
      [kitty]
      # Use kitty's regular clipboard for both copy and paste
      meta_mac.c = C-S-c
      meta_mac.v = C-S-v
      # Keep Meta-T distinct from Ctrl-T so terminal applications still receive Ctrl-T
      meta_mac.t = C-S-t

      [cs2]
      control = layer(control)
      leftmeta = layer(meta)

      # Minecraft on native Wayland uses app_id "com.mojang.minecraft" -> com-mojang-minecraft;
      # under XWayland its class is the initial title, e.g. "Minecraft* 1.21.1" -> minecraft-1-21-1
      [*minecraft*]
      control = layer(control)
      leftmeta = layer(meta)
    '';
  };

  # keyd maps Meta-T to Ctrl-Shift-T only in kitty; leave Ctrl-T to the terminal
  home-manager.users.moeleak.programs.kitty.keybindings = {
    "ctrl+shift+t" = "new_tab";
    "ctrl+shift+[" = "previous_tab";
    "ctrl+shift+]" = "next_tab";
  };
}
