let
  username = "moeleak";
  hostName = "lp4a";
  publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMz+2frjnWmRB86/XlWOaPLxSWnQRIAwf7x83v8xTaHw i@leak.moe";
in
{
  networking.hostName = hostName;

  users.users."${username}" = {
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [
      "users"
      "wheel"
      "docker"
    ];
    openssh.authorizedKeys.keys = [ publicKey ];
  };

  users.users.root.openssh.authorizedKeys.keys = [ publicKey ];

  users.groups = {
    "${username}" = { };
    docker = { };
  };
}
