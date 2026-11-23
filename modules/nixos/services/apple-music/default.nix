# The Apple Music Telegram bot, in three containers:
#
# - apple-music-wrapper, the decryption wrapper for an Apple Music account,
#   on 127.0.0.1:10020/20020/30020. Its patched build's source is gone, so its
#   image is the one exported from as3 on 2026-11-20 (wrapperImage below,
#   backed up in /var/backups on an4).
#   Its account data is in /var/lib/apple-music-wrapper.
# - telegram-bot-api, a local Telegram Bot API server on 127.0.0.1:8080, from
#   nixpkgs; it reads the bot's downloads to upload them.
# - apple-music-downloader-bot, the bot (pkgs/apple-music-bot), on the host's
#   network to reach both; its data and downloads are in
#   /var/lib/apple-music-bot.
#
# Secrets, in secrets/apple-music.yaml: `apple-music/bot-config` (the bot's
# whole config.yaml, tokens and settings), `apple-music/wrapper-env`
# (USERNAME and PASSWORD of the account) and `apple-music/telegram-env`
# (TELEGRAM_API_ID and TELEGRAM_API_HASH).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.apple-music;
  secret = name: config.sops.secrets."apple-music/${name}".path;
  image = img: "${img.imageName}:${img.imageTag}";

  bot = pkgs.callPackage ../../../../pkgs/apple-music-bot { src = inputs.apple-music-bot; };

  # What the bot's Dockerfile installs: MP4Box (GPAC), ffmpeg and ffprobe.
  # MP4Box tags a file by writing it anew in /app, then moving it over the
  # old one in /downloads, another file system, which takes sh and mv.
  botImage = pkgs.dockerTools.streamLayeredImage {
    name = "apple-music-bot";
    contents = [
      pkgs.gpac
      pkgs.ffmpeg-headless
      pkgs.bashNonInteractive
      pkgs.coreutils
    ];
    extraCommands = ''
      mkdir -p app/data downloads/ALAC tmp
      chmod 1777 tmp
    '';
    config = {
      Entrypoint = [ (lib.getExe bot) ];
      WorkingDir = "/app";
      Env = [
        "PATH=/bin"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
    };
  };

  # It reads TELEGRAM_API_ID and TELEGRAM_API_HASH from the environment.
  telegramImage = pkgs.dockerTools.streamLayeredImage {
    name = "telegram-bot-api";
    extraCommands = ''
      mkdir -p var/lib/telegram-bot-api tmp
      chmod 1777 tmp
    '';
    config.Entrypoint = [
      (lib.getExe pkgs.telegram-bot-api)
      "--local"
      "--http-port=8081"
      "--dir=/var/lib/telegram-bot-api"
      "--temp-dir=/tmp"
    ];
  };

  wrapperImage = pkgs.requireFile {
    name = "apple-music-wrapper-dnsfix-20260924.tar.gz";
    hash = "sha256-eXLEh+la+8bfn8zukhE0VRCwc2+vmGn8YKw0EBsoJ40=";
    message = ''
      The wrapper's image cannot be rebuilt. It was exported from as3 with
        docker save wrapper:dnsfix-20260924 | gzip -n
      and a copy is in /var/backups on an4. Add it to the store with
        nix-store --add-fixed sha256 apple-music-wrapper-dnsfix-20260924.tar.gz
    '';
  };
in
{
  options.my.services.apple-music = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    sops.secrets = lib.genAttrs [
      "apple-music/bot-config"
      "apple-music/wrapper-env"
      "apple-music/telegram-env"
    ] (_: { });

    systemd.tmpfiles.rules = [
      "d /var/lib/apple-music-bot/data 0755 root root -"
      "d /var/lib/apple-music-bot/downloads 0755 root root -"
      "d /var/lib/apple-music-wrapper/data 0755 root root -"
    ];

    # The wrapper dies on a FairPlay error it cannot recover from (as on
    # 2026-11-23: KDCanProcessCKC -42786 while refreshing its decrypt
    # context), yet its launcher exits 0, so oci-containers' on-failure never
    # restarts it and the bot is left with nothing on 127.0.0.1:10020.
    systemd.services.docker-apple-music-wrapper.serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = 5;
    };

    virtualisation.oci-containers = {
      backend = "docker";
      containers = {
        apple-music-wrapper = {
          image = "wrapper:dnsfix-20260924";
          imageFile = wrapperImage;
          pull = "never";
          # The image's entrypoint logs in only while the account data is
          # missing, as Apple asks for a 2FA code at every login. It waits a
          # minute for the code in
          # /var/lib/apple-music-wrapper/data/data/com.apple.android.music/files/2fa.txt.
          # To log in again, stop the unit, write a fresh code there (codes
          # expire in minutes) and run the image once with this container's
          # volume and environment file, as
          #   ./wrapper -F -L "$USERNAME:$PASSWORD" -H 0.0.0.0
          # then remove the code file and start the unit.
          environmentFiles = [ (secret "wrapper-env") ];
          volumes = [ "/var/lib/apple-music-wrapper/data:/app/rootfs/data" ];
          ports = map (port: "127.0.0.1:${toString port}:${toString port}") [
            10020
            20020
            30020
          ];
          privileged = true;
        };

        telegram-bot-api = {
          image = image telegramImage;
          imageStream = telegramImage;
          pull = "never";
          environmentFiles = [ (secret "telegram-env") ];
          volumes = [ "/var/lib/apple-music-bot/downloads:/downloads:ro" ];
          ports = [ "127.0.0.1:8080:8081" ];
        };

        apple-music-downloader-bot = {
          image = image botImage;
          imageStream = botImage;
          pull = "never";
          environment.TELEGRAM_CACHE_DB = "/app/data/telegram-cache.db";
          volumes = [
            "${secret "bot-config"}:/app/config.yaml:ro"
            "/var/lib/apple-music-bot/data:/app/data"
            "/var/lib/apple-music-bot/downloads:/downloads"
          ];
          extraOptions = [ "--network=host" ];
          dependsOn = [
            "apple-music-wrapper"
            "telegram-bot-api"
          ];
        };
      };
    };
  };
}
