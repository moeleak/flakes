{ pkgs, ... }:
{
  services.sunshine = {
    enable = true;
    autoStart = true; # optional: starts Sunshine automatically on login
    capSysAdmin = true;
  };
  services.sunshine.package = pkgs.sunshine.override {
    cudaSupport = true;
    cudaPackages = pkgs.cudaPackages;
  };
}
