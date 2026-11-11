{
  my.services.keyd = {
    tapTimeout = 200;
    main = ''
      capslock = overload(control, esc)
      control = overload(control, esc)
      leftmeta = overload(meta_mac, leftmeta)
    '';
    cmdLayer = {
      # Cmd-1 … Cmd-9 switch workspaces in sway
      digits = "M";
      bindings = ''
        space = M-space
        enter = M-enter

        h = M-h
        j = M-j
        k = M-k
        l = M-l
      '';
    };
  };
}
