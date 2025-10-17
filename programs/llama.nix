{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (pkgs.llama-cpp.override { cudaSupport = true; })
  ];
}
