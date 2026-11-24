# Debian 13 on Lab, a node on DN42 (vm1.moeleak.dn42); see lib/vms.nix.
{
  id = 5;
  image = "debian-13";
  cores = 8;
  memory = 64;
  disk = 1024;
  egress = "as3";
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMz+2frjnWmRB86/XlWOaPLxSWnQRIAwf7x83v8xTaHw i@leak.moe"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID3iRKF+sC6KDwda+PNf9HQ2lU8SXFJ6Eqh1aUQybZi/"
  ];
  dn42.publicKey = "wEfqkAjKCvBa3tTqSem0e5rTw2mOr/4pg+93nLnt9mc=";
}
