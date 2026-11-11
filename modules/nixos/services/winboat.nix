{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.winboat;
in
{
  options.my.services.winboat = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    users.users.${config.my.user}.extraGroups = [
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
      pkgs.freerdp
    ];
  };
}
