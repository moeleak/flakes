{
  pkgs,
  ...
}:

{
  users.users.moeleak.extraGroups = [
    "libvirtd"
  ];
  virtualisation = {
    libvirtd = {
      enable = true;
      package = pkgs.libvirt;
      qemu = {
        package = pkgs.qemu;
        swtpm = {
          enable = false;
          package = pkgs.swtpm;
        };
      };
    };
    spiceUSBRedirection.enable = true;
  };
  services.spice-vdagentd.enable = true;
  programs.virt-manager.enable = true;

  environment.systemPackages = [
    pkgs.winboat
    pkgs.freerdp
  ];
}
