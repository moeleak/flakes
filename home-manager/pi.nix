{ config, ... }:
{
  programs.pi-coding-agent.enable = true;

  # Pi discovers extension directories automatically. Keep the package and
  # extension declarative while settings, credentials and sessions stay writable.
  home.file = {
    "${config.programs.pi-coding-agent.configDir}/extensions/rescue".source =
      ../programs/pi/extensions/rescue;
    "${config.programs.pi-coding-agent.configDir}/extensions/token-speed".source =
      ../programs/pi/extensions/token-speed;
    "${config.programs.pi-coding-agent.configDir}/extensions/unix-keys".source =
      ../programs/pi/extensions/unix-keys;
  };
}
