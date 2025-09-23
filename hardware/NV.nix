{ config, pkgs, ... }:

{
  hardware.graphics.enable = true;
  hardware.nvidia.open = true;
  hardware.nvidia.powerManagement.enable = false;
  services.xserver.videoDrivers = [ "nvidia" ];
  environment.systemPackages = with pkgs; [
    # ollama-cuda # wasn't cached and took forever to build
    nvtopPackages.nvidia
    cudaPackages.cudatoolkit
  ];
}
