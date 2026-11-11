{ config, lib, ... }:
{
  programs.pi-coding-agent.enable = true;

  # Pi discovers extension directories automatically. Every directory in
  # ./extensions is deployed; settings, credentials and sessions stay writable.
  home.file = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "${config.programs.pi-coding-agent.configDir}/extensions/${name}" {
      source = ./extensions + "/${name}";
    }
  ) (builtins.readDir ./extensions);
}
