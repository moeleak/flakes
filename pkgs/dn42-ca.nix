# DN42's root certificate alone, from nixpkgs' dn42-cacert. That file starts
# with `openssl x509 -text` output, which Firefox's certificate policy cannot
# parse: it only strips what precedes the PEM header on the header's own line.
# The root's Name Constraints let it vouch only for .dn42, 172.20.0.0/14 and
# fd42::/16.
{ dn42-cacert, runCommandLocal }:
runCommandLocal "dn42-ca.pem" { } ''
  sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
    ${dn42-cacert}/etc/ssl/certs/dn42-ca.crt > $out
''
