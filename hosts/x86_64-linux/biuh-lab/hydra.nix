{
  config,
  lib,
  pkgs,
  ...
}:

let
  hydraHost = "hydra.leak.moe";
  cacheHost = "cache.leak.moe";
  hydraUrl = "https://${hydraHost}";
  secretsFile = ../../../secrets/hydra.yaml;

  secret = name: config.sops.secrets.${name}.path;
  r2Bucket = "nix-cache";
  r2PendingRoots = "/nix/var/nix/gcroots/hydra-r2-pending";
  # Cloudflare measures the free allowance in decimal GB-month. Keep 100 MB
  # free so metadata and a partially completed request cannot cross 10 GB.
  r2StorageLimitBytes = 9900000000;
  r2UpstreamCaches = [
    "https://cache.nixos.org"
    "https://devenv.cachix.org"
  ];

  cloudflaredConfig = pkgs.writeText "hydra-cloudflared.json" (
    builtins.toJSON {
      ingress = [
        {
          hostname = hydraHost;
          service = "http://127.0.0.1:3000";
        }
        { service = "http_status:404"; }
      ];
    }
  );

  runCloudflared = pkgs.writeShellApplication {
    name = "run-hydra-cloudflared";
    runtimeInputs = [
      pkgs.cloudflared
      pkgs.jq
    ];
    text = ''
      credentials="$CREDENTIALS_DIRECTORY/tunnel.json"
      tunnel_id="$(jq -er '.TunnelID | select(test("^[0-9a-fA-F-]{36}$"))' "$credentials")"

      exec cloudflared tunnel \
        --config=${cloudflaredConfig} \
        --credentials-file="$credentials" \
        --no-autoupdate \
        --protocol=http2 \
        run "$tunnel_id"
    '';
  };

  checkHydraSecrets = pkgs.writeShellApplication {
    name = "check-hydra-secrets";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      check_placeholder() {
        if grep -q 'CHANGE_ME' "$1"; then
          echo "Hydra deployment secret is still a CHANGE_ME placeholder: $1" >&2
          exit 1
        fi
      }

      check_placeholder ${lib.escapeShellArg (secret "r2-account-id")}
      check_placeholder ${lib.escapeShellArg (secret "r2-access-key-id")}
      check_placeholder ${lib.escapeShellArg (secret "r2-secret-access-key")}
      check_placeholder ${lib.escapeShellArg (secret "hydra-admin-password")}
      check_placeholder ${lib.escapeShellArg (secret "cloudflare-tunnel-credentials")}

      grep -Eq '^[0-9a-fA-F]{32}$' ${lib.escapeShellArg (secret "r2-account-id")}
      test "$(wc -c < ${lib.escapeShellArg (secret "r2-access-key-id")})" -ge 16
      test "$(wc -c < ${lib.escapeShellArg (secret "r2-secret-access-key")})" -ge 16
      test "$(wc -c < ${lib.escapeShellArg (secret "hydra-admin-password")})" -ge 32
      grep -Eq '^cache\.leak\.moe-1:[A-Za-z0-9+/]+={0,2}$' \
        ${lib.escapeShellArg (secret "hydra-cache-signing-key")}
      jq -e '
        (.AccountTag | type == "string" and length > 0) and
        (.TunnelID | test("^[0-9a-fA-F-]{36}$")) and
        (.TunnelSecret | type == "string" and length > 0)
      ' ${lib.escapeShellArg (secret "cloudflare-tunnel-credentials")} >/dev/null
    '';
  };

  uploadHydraCache = pkgs.writeShellApplication {
    name = "upload-hydra-cache-to-r2";
    runtimeInputs = [
      pkgs.awscli2
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.nix
      pkgs.util-linux
    ];
    text = builtins.readFile ./hydra-r2-uploader.sh;
  };
in
{
  sops = {
    secrets = {
      r2-account-id = {
        sopsFile = secretsFile;
        restartUnits = [ "hydra-secrets-check.service" ];
      };
      r2-access-key-id = {
        sopsFile = secretsFile;
        restartUnits = [ "hydra-secrets-check.service" ];
      };
      r2-secret-access-key = {
        sopsFile = secretsFile;
        restartUnits = [ "hydra-secrets-check.service" ];
      };
      hydra-admin-password = {
        sopsFile = secretsFile;
        owner = "hydra";
        group = "hydra";
        mode = "0400";
        restartUnits = [
          "hydra-secrets-check.service"
          "hydra-bootstrap.service"
        ];
      };
      hydra-cache-signing-key = {
        sopsFile = secretsFile;
        owner = "hydra-queue-runner";
        group = "hydra";
        mode = "0400";
        restartUnits = [ "hydra-secrets-check.service" ];
      };
      cloudflare-tunnel-credentials = {
        sopsFile = secretsFile;
        restartUnits = [
          "hydra-secrets-check.service"
          "hydra-cloudflared.service"
        ];
      };
    };

    templates = {
      "hydra-r2-credentials" = {
        owner = "hydra-queue-runner";
        group = "hydra";
        mode = "0400";
        content = ''
          [default]
          aws_access_key_id=${config.sops.placeholder.r2-access-key-id}
          aws_secret_access_key=${config.sops.placeholder.r2-secret-access-key}
          region=auto
        '';
        restartUnits = [ "hydra-secrets-check.service" ];
      };

      "hydra-r2-uploader.env" = {
        owner = "hydra-queue-runner";
        group = "hydra";
        mode = "0400";
        content = ''
          R2_ENDPOINT=https://${config.sops.placeholder.r2-account-id}.r2.cloudflarestorage.com
        '';
      };

      "hydra-r2.conf" = {
        owner = "hydra";
        group = "hydra";
        mode = "0440";
        content = ''
          binary_cache_public_uri = https://${cacheHost}
          upload_logs_to_binary_cache = false
        '';
        restartUnits = [
          "hydra-secrets-check.service"
          "hydra-server.service"
          "hydra-queue-runner.service"
        ];
      };

      # The C++ queue runner does not process Config::General Include
      # directives. Keep its flat configuration deliberately local; the
      # quota-aware uploader below is the only component allowed to write R2.
      "hydra-queue-runner.conf" = {
        owner = "hydra-queue-runner";
        group = "hydra";
        mode = "0400";
        content = ''
          upload_logs_to_binary_cache = false
          queue_runner_metrics_address = 127.0.0.1:9198
          gc_roots_dir = ${config.services.hydra.gcRootsDir}
          use-substitutes = ${if config.services.hydra.useSubstitutes then "1" else "0"}
        '';
        restartUnits = [ "hydra-queue-runner.service" ];
      };
    };
  };

  services.hydra = {
    enable = true;
    hydraURL = hydraUrl;
    notificationSender = "hydra@leak.moe";
    listenHost = "127.0.0.1";
    port = 3000;
    minimumDiskFree = 512;
    minimumDiskFreeEvaluator = 512;
    useSubstitutes = true;
    extraConfig = ''
      Include ${config.sops.templates."hydra-r2.conf".path}
      server_store_uri = daemon
      allow_import_from_derivation = true
      queue_runner_metrics_address = 127.0.0.1:9198
    '';
  };

  nix.settings = {
    cores = 13;
    max-jobs = 8;
  };

  systemd.services = {
    hydra-secrets-check = {
      description = "Validate Hydra deployment secrets";
      before = [
        "hydra-init.service"
        "hydra-server.service"
        "hydra-evaluator.service"
        "hydra-queue-runner.service"
        "hydra-notify.service"
        "hydra-bootstrap.service"
        "hydra-cloudflared.service"
        "hydra-r2-uploader.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe checkHydraSecrets;
      };
    };

    hydra-init = {
      after = [ "hydra-secrets-check.service" ];
      requires = [ "hydra-secrets-check.service" ];
    };

    hydra-server = {
      after = [ "hydra-secrets-check.service" ];
      requires = [ "hydra-secrets-check.service" ];
    };

    hydra-evaluator = {
      after = [ "hydra-secrets-check.service" ];
      requires = [ "hydra-secrets-check.service" ];
    };

    hydra-queue-runner = {
      after = [ "hydra-secrets-check.service" ];
      requires = [ "hydra-secrets-check.service" ];
      environment = {
        HYDRA_CONFIG = lib.mkForce config.sops.templates."hydra-queue-runner.conf".path;
      };
    };

    hydra-r2-uploader = {
      description = "Upload the filtered Hydra cache to Cloudflare R2";
      after = [
        "hydra-secrets-check.service"
        "hydra-update-gc-roots.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      requires = [
        "hydra-secrets-check.service"
        "hydra-update-gc-roots.service"
      ];
      environment = {
        AWS_EC2_METADATA_DISABLED = "true";
        AWS_REGION = "auto";
        AWS_SHARED_CREDENTIALS_FILE = config.sops.templates."hydra-r2-credentials".path;
        HYDRA_GC_ROOTS = config.services.hydra.gcRootsDir;
        R2_BUCKET = r2Bucket;
        R2_PENDING_ROOTS = r2PendingRoots;
        R2_SIGNING_KEY = secret "hydra-cache-signing-key";
        R2_STORAGE_LIMIT_BYTES = toString r2StorageLimitBytes;
        R2_UPSTREAM_CACHES = lib.concatStringsSep " " r2UpstreamCaches;
      };
      serviceConfig = {
        Type = "oneshot";
        User = "hydra-queue-runner";
        Group = "hydra";
        EnvironmentFile = config.sops.templates."hydra-r2-uploader.env".path;
        ExecStart = lib.getExe uploadHydraCache;
        StateDirectory = "hydra-r2-uploader";
        StateDirectoryMode = "0700";
        UMask = "0077";
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "6h";
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ r2PendingRoots ];
        NoNewPrivileges = true;
      };
    };

    hydra-notify = {
      after = [ "hydra-secrets-check.service" ];
      requires = [ "hydra-secrets-check.service" ];
    };

    hydra-bootstrap = {
      description = "Create the Hydra administrator, project, and flake jobset";
      wantedBy = [ "multi-user.target" ];
      after = [ "hydra-server.service" ];
      requires = [ "hydra-server.service" ];
      path = [
        config.services.hydra.package
        pkgs.curl
        pkgs.jq
      ];
      environment = {
        HYDRA_CONFIG = "/var/lib/hydra/hydra.conf";
        HYDRA_DATA = "/var/lib/hydra";
        HYDRA_DBI = "dbi:Pg:dbname=hydra;user=hydra;";
      };
      script = ''
        set -euo pipefail

        url=http://127.0.0.1:3000
        runtime_dir="$RUNTIME_DIRECTORY"
        login_json="$runtime_dir/login.json"
        cookie_jar="$runtime_dir/cookies"
        project_json="$runtime_dir/project.json"
        jobset_json="$runtime_dir/jobset.json"
        trap 'rm -f "$login_json" "$cookie_jar" "$project_json" "$jobset_json"' EXIT

        for attempt in $(seq 1 60); do
          if curl --fail --silent "$url/" >/dev/null; then
            break
          fi
          if [ "$attempt" -eq 60 ]; then
            echo "Hydra did not become ready within 60 seconds" >&2
            exit 1
          fi
          sleep 1
        done

        password="$(<${lib.escapeShellArg (secret "hydra-admin-password")})"
        printf '%s\n%s\n' "$password" "$password" \
          | hydra-create-user moeleak \
              --full-name MoeLeak \
              --email-address i@leak.moe \
              --password-prompt \
              --wipe-roles \
              --role admin

        jq -n --arg password "$password" \
          '{ username: "moeleak", password: $password }' > "$login_json"
        unset password

        request=(
          curl
          --fail
          --silent
          --show-error
          --header 'Accept: application/json'
          --header 'Content-Type: application/json'
          --header "Origin: $url"
          --referer "$url/"
        )

        "''${request[@]}" \
          --request POST \
          --data-binary "@$login_json" \
          --cookie-jar "$cookie_jar" \
          "$url/login" >/dev/null

        jq -n '{ displayname: "NixOS Flakes", enabled: 1, visible: 1 }' \
          > "$project_json"
        "''${request[@]}" \
          --request PUT \
          --data-binary "@$project_json" \
          --cookie "$cookie_jar" \
          "$url/project/flakes" >/dev/null

        jq -n '{
          type: 1,
          flake: "github:moeleak/flakes/main",
          description: "NixOS system closures from github:moeleak/flakes/main",
          checkinterval: 300,
          schedulingshares: 100,
          enabled: 1,
          visible: 1,
          keepnr: 3,
          emailoverride: ""
        }' > "$jobset_json"
        "''${request[@]}" \
          --request PUT \
          --data-binary "@$jobset_json" \
          --cookie "$cookie_jar" \
          "$url/jobset/flakes/main" >/dev/null
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "hydra";
        Group = "hydra";
        RuntimeDirectory = "hydra-bootstrap";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
      };
    };

    hydra-cloudflared = {
      description = "Cloudflare Tunnel for Hydra";
      wantedBy = [ "multi-user.target" ];
      after = [
        "hydra-server.service"
        "hydra-secrets-check.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      requires = [
        "hydra-server.service"
        "hydra-secrets-check.service"
      ];
      serviceConfig = {
        DynamicUser = true;
        ExecStart = lib.getExe runCloudflared;
        LoadCredential = "tunnel.json:${secret "cloudflare-tunnel-credentials"}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };

  systemd.timers.hydra-r2-uploader = {
    description = "Periodically upload the filtered Hydra cache to R2";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "2min";
      OnUnitInactiveSec = "30min";
      RandomizedDelaySec = "2min";
      Unit = "hydra-r2-uploader.service";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${r2PendingRoots} 0750 hydra-queue-runner hydra -"
  ];
}
