{
  ...
}:

{
  users.users.moeleak.extraGroups = [
    "docker"
  ];
  users.users.ziyanxiao.extraGroups = [
    "docker"
  ];
  virtualisation = {
    docker = {
      enable = true;
      rootless.enable = true;
    };
  };
}
