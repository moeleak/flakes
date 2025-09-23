{ ... }:

{
  virtualisation.docker = {
    enable = true;
    rootless.enable = true;
  };
  users.users.moeleak.extraGroups = [ "docker" ];
}
