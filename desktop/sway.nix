{
  config,
  lib,
  pkgs,
  ...
}:

let
  fcitx5Enabled =
    config.i18n.inputMethod.enable && config.i18n.inputMethod.type == "fcitx5";
  quietBoot = pkgs.stdenv.hostPlatform.system != "riscv64-linux";
  pipewireEnabled = config.services.pipewire.enable;
  swayStatus = pkgs.writeShellScript "sway-status" ''
    ${lib.optionalString pipewireEnabled ''
      volume_status() {
        output=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
        [ -n "$output" ] || return 1

        volume=$(printf '%s\n' "$output" | ${pkgs.gawk}/bin/awk '$1 == "Volume:" && $2 ~ /^[0-9.]+$/ { printf "%d", ($2 * 100) + 0.5 }')
        [ -n "$volume" ] || return 1

        case "$output" in
          *"[MUTED]"*) printf 'VOL mute' ;;
          *) printf 'VOL %s%%' "$volume" ;;
        esac
      }
    ''}
    ${lib.optionalString (!pipewireEnabled) ''
      volume_status() {
        return 1
      }
    ''}

    brightness_status() {
      for brightness in /sys/class/backlight/*/brightness; do
        [ -e "$brightness" ] || continue

        dir=''${brightness%/brightness}
        current=$(${pkgs.coreutils}/bin/cat "$brightness" 2>/dev/null || true)
        max=$(${pkgs.coreutils}/bin/cat "$dir/max_brightness" 2>/dev/null || true)

        [ "$max" -gt 0 ] 2>/dev/null || continue

        percent=$(( (current * 100 + max / 2) / max ))
        printf 'BRI %s%%' "$percent"
        return 0
      done

      return 1
    }

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

    append_part() {
      [ -n "$1" ] || return 0

      if [ -n "$line" ]; then
        line="$line | $1"
      else
        line="$1"
      fi
    }

    while :; do
      line=

      if volume=$(volume_status); then
        append_part "$volume"
      fi
      if brightness=$(brightness_status); then
        append_part "$brightness"
      fi
      if battery=$(battery_status); then
        append_part "$battery"
      fi
      append_part "$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M')"

      printf '%s\n' "$line"
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
  swayConfig = pkgs.runCommand "sway-config" { } ''
    substitute ${config.programs.sway.package}/etc/sway/config $out \
      --replace-fail "status_command while date +'%Y-%m-%d %X'; do sleep 1; done" \
                     "icon_theme Adwaita"$'\n'"    status_command ${swayStatus}"
  '';
in
lib.mkMerge [
  {
    programs.sway = {
      enable = true;
      extraSessionCommands = lib.mkBefore ''
        export XDG_DATA_DIRS="/run/current-system/sw/share''${XDG_DATA_DIRS:+:}''${XDG_DATA_DIRS:-}"
      '';
      wrapperFeatures.gtk = true;
    };

    fonts.packages = lib.mkAfter [
      pkgs.nerd-fonts._0xproto
      pkgs.noto-fonts-cjk-sans
    ];

    environment.systemPackages = lib.mkAfter [
      pkgs.adwaita-icon-theme
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
    environment.etc."sway/config.d/30-brightness.conf".text = ''
      bindsym --locked $mod+F5 exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
      bindsym --locked $mod+F6 exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%+
    '';
    environment.etc."sway/config".source = lib.mkForce swayConfig;

    services.greetd = {
      enable = true;
      useTextGreeter = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
          user = "greeter";
        };
      };
    };
  }

  (lib.mkIf quietBoot {
    boot = {
      consoleLogLevel = 0;
      initrd.verbose = false;
      kernelParams = lib.mkAfter [
        "quiet"
        "udev.log_level=3"
      ];
    };
  })

  (lib.mkIf fcitx5Enabled {
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
    environment.etc."sway/config.d/40-volume.conf".text = ''
      bindsym --locked $mod+F8 exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
      bindsym --locked $mod+F9 exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
      bindsym --locked $mod+F10 exec ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
    '';
  })
]
