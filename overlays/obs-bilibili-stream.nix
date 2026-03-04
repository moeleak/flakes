final: prev: {
  obs-bilibili-stream = prev.callPackage ../pkgs/obs-bilibili-stream.nix { };

  obs-studio-plugins = (prev.obs-studio-plugins or { }) // {
    inherit (final) obs-bilibili-stream;
  };
}
