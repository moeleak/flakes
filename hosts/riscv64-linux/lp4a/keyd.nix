{ ... }:

{
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.global.overload_tap_timeout = 200;
      extraConfig = ''
        [main]
        capslock = overload(control, esc)
        control = overload(control, esc)
        leftmeta = overload(meta_mac, leftmeta)

        [meta_mac]
        space = M-space
        enter = M-enter

        h = M-h
        j = M-j
        k = M-k
        l = M-l

        1 = M-1
        2 = M-2
        3 = M-3
        4 = M-4
        5 = M-5
        6 = M-6
        7 = M-7
        8 = M-8
        9 = M-9

        c = C-insert
        v = S-insert
        x = S-delete

        left = home
        right = end

        tab = swapm(app_switch_state, M-tab)
        ` = A-f6

        [app_switch_state:M]
        tab = M-tab
        right = M-tab

        ` = M-S-tab
        left = M-S-tab
      '';
    };
  };
}
