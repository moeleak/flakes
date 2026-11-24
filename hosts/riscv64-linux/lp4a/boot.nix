# Booting through extlinux, as ryan4yin/nixos-licheepi4a does. The U-Boot
# here (the nixos-licheepi4a input's) runs boot.scr from the first
# partition. Its boot.scr used to load the kernel, initrd and device tree
# copied there when the image was built, with
# init=/nix/var/nix/profiles/system/init: each new generation then ran on
# that old kernel, without its own modules (on 2026-11-25, without the
# Ethernet driver). Now boot.scr hands over to extlinux.conf, which
# generic-extlinux-compatible keeps for each generation: kernel, initrd,
# device tree and init together, with a menu of generations on the serial
# console.
#
# /boot stays on the root partition, which U-Boot reads as ext4: the first
# one has 200 MiB, and a generation's kernel and initrd take over 70.
{
  config,
  lib,
  pkgs,
  pkgsKernel,
  ...
}:
let
  # SD (mmc 1) over eMMC (mmc 0), as before. U-Boot sets `mmcdev` in the
  # kernel's command line below, as it expands extlinux's APPEND.
  bootScript = pkgs.runCommand "lp4a-boot.scr" {
    nativeBuildInputs = [ pkgs.buildPackages.ubootTools ];
  } ''
    cat > boot.cmd <<'EOF'
    if test -e mmc 1:2 /boot/extlinux/extlinux.conf; then
      setenv mmcdev 1
    else
      setenv mmcdev 0
    fi
    echo "NixOS: extlinux on mmc $mmcdev:2"
    sysboot mmc $mmcdev:2 any $pxefile_addr_r /boot/extlinux/extlinux.conf
    echo "NixOS: sysboot failed"
    EOF
    mkimage -A riscv -T script -C none -n "NixOS LicheePi 4A extlinux" -d boot.cmd $out
  '';
  toplevel = config.system.build.toplevel;
in
{
  # boot.scr set it before; extlinux's APPEND is all of the command line.
  boot.kernelParams = [ "root=/dev/mmcblk\${mmcdev}p2" ];

  sdImage = {
    populateFirmwareCommands = lib.mkForce ''
      cp ${pkgsKernel.thead-opensbi}/share/opensbi/lp64/generic/firmware/fw_dynamic.bin firmware/fw_dynamic.bin
      cp ${pkgsKernel.light_aon_fpga}/lib/firmware/light_aon_fpga.bin firmware/light_aon_fpga.bin
      cp ${pkgsKernel.light_c906_audio}/lib/firmware/light_c906_audio.bin firmware/light_c906_audio.bin
      cp ${bootScript} firmware/boot.scr
    '';
    populateRootCommands = lib.mkForce ''
      mkdir -p ./files/boot ./files/nix/var/nix/profiles
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${toplevel} -d ./files/boot
      ln -s ${toplevel} ./files/nix/var/nix/profiles/system
    '';
    # To carry it to where it is flashed.
    compressImage = lib.mkForce true;
  };

  # Machines installed before get this boot.scr on their first partition,
  # beside the root one, when a generation is activated (and at each boot).
  system.activationScripts.lp4aBootScript.text = ''
    root=$(${pkgs.util-linux}/bin/findmnt -no SOURCE /)
    case "$root" in
      /dev/mmcblk[0-9]p2)
        firmware=''${root%2}1
        mnt=$(mktemp -d)
        if ${pkgs.util-linux}/bin/mount -t vfat "$firmware" "$mnt"; then
          if ! ${pkgs.diffutils}/bin/cmp -s ${bootScript} "$mnt/boot.scr"; then
            cp ${bootScript} "$mnt/boot.scr.new" && sync \
              && mv "$mnt/boot.scr.new" "$mnt/boot.scr" && sync \
              && echo "lp4a: boot.scr on $firmware now boots through extlinux"
          fi
          ${pkgs.util-linux}/bin/umount "$mnt"
        else
          echo "lp4a: could not mount $firmware for boot.scr" >&2
        fi
        rmdir "$mnt"
        ;;
    esac
  '';
}
