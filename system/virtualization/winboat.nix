{
  inputs,
  pkgs,
  system,
  ...
}:

{
  users.users.moeleak.extraGroups = [
    "libvirtd"
  ];
  virtualisation = {
    libvirtd = {
      enable = true;
      package = with pkgs; libvirt;
      qemu = {
        package = with pkgs; qemu;
        swtpm = {
          enable = false;
          package = with pkgs; swtpm;
        };
      };
    };
    spiceUSBRedirection.enable = true;
  };
  services.spice-vdagentd.enable = true;
  programs.virt-manager.enable = true;

  environment.systemPackages = [
    inputs.winboat.packages.x86_64-linux.winboat
    pkgs.freerdp
  ];
}
