let
  publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMz+2frjnWmRB86/XlWOaPLxSWnQRIAwf7x83v8xTaHw i@leak.moe";
in
{
  networking.hostName = "lp4a";

  users.users."moeleak" = {
    isNormalUser = true;
    home = "/home/moeleak";
    extraGroups = [
      "users"
      "networkmanager"
      "wheel"
      "docker"
      "video"
    ];
    openssh.authorizedKeys.keys = [ publicKey ];
  };

  users.users."junzhema" = {
    isNormalUser = true;
    home = "/home/junzhema";
    extraGroups = [
      "users"
      "networkmanager"
      "docker"
    ];
    openssh.authorizedKeys.keys = [ publicKey ];
  };

  users.users.root.openssh.authorizedKeys.keys = [ publicKey ];

  users.groups = {
    docker = { };
  };
}
