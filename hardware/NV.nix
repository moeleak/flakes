{ config, pkgs, ... }:

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
