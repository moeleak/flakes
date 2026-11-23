# archive.dn42 (`archive` in lib/dn42.nix), on DN42 only: the node
# `archive.node` serves the files in /var/lib/dn42-archive over HTTPS with
# Caddy, as a directory listing where a directory has no index.html, at the
# domain and at www, which redirects to it. dns.nix names the node in the
# domain's zone.
#
# Caddy obtains the certificate itself from DN42's ACME CA (acme.burble.dn42),
# which reaches the HTTP challenge on Caddy's port 80 over DN42. Caddy trusts
# that CA's own server by DN42's root (`ca_root`, from ../../../common/dn42-ca.nix),
# whatever the system trusts, and asks no other CA. Its certificates last 30
# days; Caddy renews them a third of that before they expire.
#
# The files are root's: copy them there, as root, with rsync or scp; Caddy
# reads them as it is.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.dn42;
  dn42 = import ../../../../lib/dn42.nix;
  inherit (dn42.archive) domain;
  root = "/var/lib/dn42-archive";

  tls = ''
    tls {
      ca https://acme.burble.dn42/v1/dn42/acme/directory
      ca_root ${config.my.system.dn42-ca.file}
    }
  '';
in
{
  config = lib.mkIf (cfg != null && dn42.archive.node == cfg.name) {
    systemd.tmpfiles.rules = [ "d ${root} 0755 root root -" ];

    services.caddy = {
      enable = true;
      virtualHosts = {
        ${domain}.extraConfig = ''
          ${tls}
          root * ${root}
          file_server browse
        '';
        "www.${domain}".extraConfig = ''
          ${tls}
          redir https://${domain}{uri} permanent
        '';
      };
    };
  };
}
