{ ... }:

{
  services.udev.extraHwdb = ''
    #61-pixel-keyboard.hwdb
    evdev:atkbd:dmi:bvn*:bvr*:bd*:svnGoogle:pn*:pvr*
      KEYBOARD_KEY_d8=f24
      KEYBOARD_KEY_e058=f24
  '';
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            f24 = "leftmeta";
            meta = "overload(control, esc)";
          };
        };
      };
    };
  };
}
