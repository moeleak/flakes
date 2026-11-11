{
  services.udev.extraHwdb = ''
    #61-pixel-keyboard.hwdb
    evdev:atkbd:dmi:bvn*:bvr*:bd*:svnGoogle:pn*:pvr*
      KEYBOARD_KEY_d8=f24
      KEYBOARD_KEY_e058=f24
  '';

  my.services.keyd.main = ''
    f24 = leftmeta
    meta = overload(control, esc)
  '';

  home-manager.users.moeleak.programs.kitty.keybindings = {
    "alt+t" = "new_tab";
    "alt+shift+[" = "previous_tab";
    "alt+shift+]" = "next_tab";
  };
}
