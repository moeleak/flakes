# The images the VMs start from (lib/vms.nix), each pinned to a dated build.
# A VM's disk is a copy made when it is first created, so changing an image
# here only affects VMs created afterwards.
{ fetchurl }:
{
  # Debian 13 (trixie), genericcloud: the cloud kernel (linux-image-cloud-amd64),
  # cloud-init. https://cloud.debian.org/images/cloud/trixie/
  debian-13 = fetchurl {
    url = "https://cloud.debian.org/images/cloud/trixie/20261123-2671/debian-13-genericcloud-amd64-20261123-2671.qcow2";
    sha512 = "76488ba3bea2349cc595fedad7748b8ba98d6b36da398eaf2bbbae3db896ba1017d4ff41cd277926784cef2c1c11145a0d600f9b4afde9b8f174d698db0cda03";
  };
}
