{
  inputs,
  pkgs,
  system,
  ...
}:

{
  users.users.moeleak.extraGroups = [
    "docker"
  ];
  virtualisation = {
    docker = {
      enable = true;
      rootless.enable = true;
    };
  };
}
