{ config, pkgs, ... }:

# CDI only mounts the 64-bit driver. 32-bit games rendered through VirtualGL in
# containers need the i386 GL/EGL libraries at Ubuntu's multiarch path, plus an
# EGL vendor file naming the library so each architecture resolves its own copy.
let
  nvidia = config.hardware.nvidia.package;
  eglVendor = pkgs.writeText "10_nvidia.json" (
    builtins.toJSON {
      file_format_version = "1.0.0";
      ICD.library_path = "libEGL_nvidia.so.0";
    }
  );
  lib32 = [
    "libEGL_nvidia.so.0"
    "libGLX_nvidia.so.0"
    "libnvidia-eglcore.so.${nvidia.version}"
    "libnvidia-glcore.so.${nvidia.version}"
    "libnvidia-glsi.so.${nvidia.version}"
    "libnvidia-tls.so.${nvidia.version}"
    "libnvidia-gpucomp.so.${nvidia.version}"
  ];
in
{
  hardware.nvidia-container-toolkit.mounts =
    map (name: {
      hostPath = "${nvidia.lib32}/lib/${name}";
      containerPath = "/usr/lib/i386-linux-gnu/${name}";
    }) lib32
    ++ [
      {
        hostPath = "${eglVendor}";
        containerPath = "/usr/share/glvnd/egl_vendor.d/10_nvidia.json";
      }
    ];
}
