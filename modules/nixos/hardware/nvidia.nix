{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.hardware.nvidia;

  # CDI only mounts the 64-bit driver. 32-bit games rendered through VirtualGL in
  # containers need the i386 GL/EGL libraries at Ubuntu's multiarch path, plus an
  # EGL vendor file naming the library so each architecture resolves its own copy.
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
  options.my.hardware.nvidia = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          # Drive the fan with a sine curve through nvidia-settings.
          fanControl = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          # Mount the 32-bit GL/EGL libraries into containers.
          container32 = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
        };
      }
    );
    default = null;
  };

  config = lib.mkIf (cfg != null) (
    lib.mkMerge [
      {
        hardware.graphics.enable = true;
        hardware.nvidia.open = true;
        hardware.nvidia.powerManagement.enable = false;
        hardware.nvidia-container-toolkit.enable = true;
        services.xserver.videoDrivers = [ "nvidia" ];
        environment.systemPackages = with pkgs; [
          nvtopPackages.nvidia
          cudaPackages.cudatoolkit
        ];
      }
      (lib.mkIf cfg.fanControl {
        systemd.timers.NVFanControl = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "1s";
            OnUnitActiveSec = "1s";
            # Timers are only accurate to a minute by default.
            AccuracySec = "1s";
          };
        };
        systemd.services.NVFanControl = {
          enable = true;
          description = "NVIDIA Fan Control Bash Script";
          serviceConfig = {
            Type = "oneshot";
          };
          path = [ pkgs.gawk ]; # used for sine wave curve calc
          wantedBy = [ "default.target" ];
          partOf = [ "default.target" ];
          script = ''
            declare -i gpuTemp
            declare -i gpuTempFloor
            declare -i gpuTempCeiling
            declare -i targetFanSpeed
            declare -i fallbackFanSpeed
            gpuTemp=$(/run/current-system/sw/bin/nvidia-settings -q gpucoretemp -c 0 2> /dev/null | grep -Po "(?<=: )[0-9]+(?=\.)")
            gpuTempFloor=$((gpuTemp<50 ? 50 : gpuTemp)) #minimum bound of fan curve
            gpuTempCeiling=$((gpuTempFloor>80 ? 80 : gpuTempFloor)) #maximum bound of fan curve
            targetFanSpeed=$(gawk -v temp=$gpuTempCeiling 'BEGIN{printf "%.0f", 35 * sin((temp-1.5)/10)+65}') #calculate the target fan speed based on a sine curve from x=50 to x=80. round to the nearest whole number.
            finalFanSpeed=$((targetFanSpeed>=30 && targetFanSpeed<=100 ? targetFanSpeed : 100)) #if a valid fan target wasn't calculated, turn fans on 100% as a safety measure
            echo "Current Temp: $gpuTemp | Target Fan Speed: $finalFanSpeed"
            /run/current-system/sw/bin/nvidia-settings -a GPUFanControlState=1 -a GPUTargetFanSpeed="$finalFanSpeed" -c 0
          '';
        };
      })
      (lib.mkIf cfg.container32 {
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
      })
    ]
  );
}
