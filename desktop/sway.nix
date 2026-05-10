{
  config,
  lib,
  pkgs,
  ...
}:

let
  fcitx5Enabled =
    config.i18n.inputMethod.enable && config.i18n.inputMethod.type == "fcitx5";
  pipewireEnabled = config.services.pipewire.enable;
  swayStatus = pkgs.writeShellScript "sway-status" ''
    battery_status() {
      for capacity in /sys/class/power_supply/BAT*/capacity; do
        [ -e "$capacity" ] || continue

        dir=''${capacity%/capacity}
        percent=$(${pkgs.coreutils}/bin/cat "$capacity" 2>/dev/null || true)
        status=$(${pkgs.coreutils}/bin/cat "$dir/status" 2>/dev/null || true)

        [ -n "$percent" ] || continue

        case "$status" in
          Charging) printf 'BAT %s%%+' "$percent" ;;
          *) printf 'BAT %s%%' "$percent" ;;
        esac
        return 0
      done

      return 1
    }

    while :; do
      if battery=$(battery_status); then
        printf '%s | %s\n' "$battery" "$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M')"
      else
        ${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M'
      fi
      ${pkgs.coreutils}/bin/sleep 30
    done
  '';
  swayConfig = pkgs.runCommand "sway-config" { } ''
    substitute ${config.programs.sway.package}/etc/sway/config $out \
      --replace-fail "status_command while date +'%Y-%m-%d %X'; do sleep 1; done" \
                     "status_command ${swayStatus}"
  '';
in
lib.mkMerge [
  {
    programs.sway.enable = true;

    fonts.packages = lib.mkAfter [
      pkgs.nerd-fonts._0xproto
      pkgs.noto-fonts-cjk-sans
    ];

    home-manager.users.moeleak.programs.foot = {
      enable = true;
      package = pkgs.foot;
      settings = {
        main.font = "0xProto Nerd Font Mono:size=12";
      };
    };

    environment.etc."sway/config.d/20-touchpad.conf".text = ''
      input type:touchpad {
        natural_scroll enabled
      }
    '';
    environment.etc."sway/config".source = lib.mkForce swayConfig;

    services.greetd = {
      enable = true;
      useTextGreeter = true;
      settings = {
        terminal.vt = lib.mkForce 7;
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
          user = "greeter";
        };
      };
    };
    systemd.services.greetd.serviceConfig.TTYPath = lib.mkForce "/dev/tty7";
  }

  (lib.mkIf fcitx5Enabled {
    i18n.inputMethod.fcitx5.settings.globalOptions."Behavior/DisabledAddons"."0" =
      "notificationitem";

    programs.sway.extraSessionCommands = lib.mkAfter ''
      export XMODIFIERS=@im=fcitx
      export GTK_IM_MODULE=fcitx
      export QT_IM_MODULE=fcitx
      export SDL_IM_MODULE=fcitx
    '';

    environment.etc."sway/config.d/10-fcitx5.conf".text = ''
      exec ${config.i18n.inputMethod.package}/bin/fcitx5 -d --replace
      exec dbus-update-activation-environment --systemd XMODIFIERS GTK_IM_MODULE QT_IM_MODULE SDL_IM_MODULE
    '';
  })

  (lib.mkIf pipewireEnabled {
    environment.etc."sway/config.d/30-volume.conf".text = ''
      bindsym --locked $mod+F8 exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
      bindsym --locked $mod+F9 exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
      bindsym --locked $mod+F10 exec ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
    '';
  })
]
