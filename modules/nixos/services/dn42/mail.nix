# The mail of `domain` (lib/dn42.nix), on DN42 only. The node `mail.node`
# takes it as mail.<domain>, the zone's MX (dns.nix), on the mail's own DN42
# addresses (`mail.ipv4` and `mail.ipv6`), which it puts on its dummy `dn42`
# beside its own, and sends from them, so that they, its name and its HELO
# agree. Postfix on port 25 hands the mail to Dovecot (LMTP), which keeps the
# mailboxes in /var/lib/vmail and serves them over IMAP with implicit TLS
# (993); the mailboxes send through Postfix's submissions (465), with
# Dovecot's logins, to .dn42 addresses only.
#
# OpenDKIM, Postfix's milter, signs with DKIM (`mail.dkim` in lib/dn42.nix)
# what the submissions and the node itself send, and checks the signatures of
# what comes in.
#
# The certificate of mail.<domain> comes from DN42's ACME CA
# (acme.burble.dn42), which reaches lego's HTTP challenge over DN42 through
# Caddy's port 80. Its certificates last 30 days.
#
# Postfix only listens on addresses already on an interface, and the DN42
# ones are on the dummy `dn42`, so Postfix and Dovecot wait for it.
#
# Secrets: `dn42-mail/<mailbox>`, the crypt(3) hash of the mailbox's
# password, as `mkpasswd` makes it, and `dn42-dkim/<selector>`, the DKIM
# private key (PEM).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.dn42;
  dn42 = import ../../../../lib/dn42.nix;
  inherit (dn42) domain;
  inherit (dn42) mail;
  inherit (mail) mailboxes dkim;

  host = "mail.${domain}";
  address = name: "${name}@${domain}";
  # The roles' mail goes to the first mailbox.
  aliases = lib.genAttrs [
    "postmaster"
    "hostmaster"
    "abuse"
    "root"
  ] (_: lib.head mailboxes);

  certificate = config.security.acme.certs.${host}.directory;
  # lego's HTTP challenge, behind Caddy's port 80.
  acmePort = 18081;
  vmail = "/var/lib/vmail";
  # Dovecot's sockets for Postfix, in its queue's private directory, where
  # Postfix's private/ names are.
  private = "${config.services.postfix.settings.main.queue_directory}/private";
  addressesUp = "systemd-networkd-wait-online@dn42:routable.service";
  milter = "unix:/run/opendkim/opendkim.sock";

  # What the submissions may send to.
  recipients = pkgs.writeText "dn42-mail-recipients" ''
    /\.dn42$/ OK
    /./ REJECT Mail goes to .dn42 addresses only
  '';
in
{
  config = lib.mkIf (cfg != null && mail.node == cfg.name) {
    # BIRD gives them to the other nodes, as it does the node's own.
    systemd.network.networks."60-dn42".address = [
      "${mail.ipv4}/32"
      "${mail.ipv6}/128"
    ];

    sops = {
      secrets = lib.genAttrs (map (mailbox: "dn42-mail/${mailbox}") mailboxes) (_: { }) // {
        "dn42-dkim/${dkim.selector}" = {
          owner = config.services.opendkim.user;
          # Where OpenDKIM looks for the selector's key.
          path = "${config.services.opendkim.keyPath}/${dkim.selector}.private";
          restartUnits = [ "opendkim.service" ];
        };
      };
      templates."dovecot-passwd" = {
        content = lib.concatMapStrings (
          mailbox: "${address mailbox}:{CRYPT}${config.sops.placeholder."dn42-mail/${mailbox}"}\n"
        ) mailboxes;
        owner = config.services.dovecot2.settings.default_internal_user;
        restartUnits = [ "dovecot.service" ];
      };
    };

    # The mailboxes' owner: a fixed ID, as the mail outlives the system.
    users.users.vmail = {
      isSystemUser = true;
      uid = 5000;
      group = "vmail";
      home = vmail;
    };
    users.groups.vmail.gid = 5000;
    systemd.tmpfiles.rules = [ "d ${vmail} 0700 vmail vmail -" ];

    security.acme = {
      acceptTerms = true;
      certs.${host} = {
        server = "https://acme.burble.dn42/v1/dn42/acme/directory";
        listenHTTP = "127.0.0.1:${toString acmePort}";
        validMinDays = 10;
        reloadServices = [
          "postfix.service"
          "dovecot.service"
        ];
      };
    };

    services.caddy = {
      enable = true;
      virtualHosts."http://${host}".extraConfig = ''
        handle /.well-known/acme-challenge/* {
          reverse_proxy 127.0.0.1:${toString acmePort}
        }
        handle {
          respond 404
        }
      '';
    };

    services.postfix = {
      enable = true;
      enableSubmissions = true;
      submissionsOptions = {
        smtpd_sasl_auth_enable = "yes";
        smtpd_sasl_type = "dovecot";
        smtpd_sasl_path = "private/auth";
        smtpd_client_restrictions = "permit_sasl_authenticated,reject";
        # master.cf splits its -o arguments at spaces.
        smtpd_recipient_restrictions = "check_recipient_access,regexp:${recipients}";
        # Which OpenDKIM signs.
        milter_macro_daemon_name = "ORIGINATING";
      };
      virtual = lib.concatStrings (
        lib.mapAttrsToList (role: mailbox: "${address role} ${address mailbox}\n") aliases
      );
      mapFiles.mailboxes = pkgs.writeText "dn42-mailboxes" (
        lib.concatMapStrings (mailbox: "${address mailbox} ${mailbox}\n") mailboxes
      );
      settings.main = {
        myhostname = host;
        mydomain = domain;
        myorigin = domain;
        # The node's own mail is for root@<domain>.
        mydestination = [ "localhost" ];
        inet_interfaces = [
          mail.ipv4
          "[${mail.ipv6}]"
          "127.0.0.1"
          "[::1]"
        ];
        smtp_bind_address = mail.ipv4;
        smtp_bind_address6 = mail.ipv6;
        mynetworks = [
          "127.0.0.0/8"
          "[::1]/128"
        ];
        virtual_mailbox_domains = [ domain ];
        virtual_mailbox_maps = [ "hash:/etc/postfix/mailboxes" ];
        virtual_transport = "lmtp:unix:private/dovecot-lmtp";
        smtpd_tls_chain_files = [
          "${certificate}/key.pem"
          "${certificate}/fullchain.pem"
        ];
        smtpd_milters = [ milter ];
        non_smtpd_milters = [ milter ];
      };
    };

    # It signs mail from `domain` that comes through the submissions or from
    # the node itself (127.0.0.1, its InternalHosts), and checks the rest.
    services.opendkim = {
      enable = true;
      domains = "csl:${domain}";
      inherit (dkim) selector;
      settings = {
        MTA = "ORIGINATING";
        Canonicalization = "relaxed/relaxed";
        # The socket for Postfix too, in OpenDKIM's group.
        UMask = "0007";
      };
    };
    users.users.postfix.extraGroups = [ config.services.opendkim.group ];

    services.dovecot2 = {
      enable = true;
      # 2.4, whose settings these are; a system older than 26.05 would get 2.3.
      package = pkgs.dovecot;
      settings = {
        dovecot_config_version = "2.4.5";
        dovecot_storage_version = "2.4.5";
        protocols = {
          imap = true;
          lmtp = true;
        };
        listen = [
          mail.ipv4
          mail.ipv6
        ];
        ssl = "required";
        ssl_server_cert_file = "${certificate}/fullchain.pem";
        ssl_server_key_file = "${certificate}/key.pem";

        "passdb passwd-file".passwd_file_path = config.sops.templates."dovecot-passwd".path;
        "userdb static".fields = {
          uid = "vmail";
          gid = "vmail";
        };
        mail_driver = "maildir";
        mail_home = "${vmail}/%{user | domain}/%{user | username}";
        mail_path = "~/Maildir";
        "namespace inbox" = {
          inbox = true;
          "mailbox Drafts" = {
            special_use = "\\Drafts";
            auto = "subscribe";
          };
          "mailbox Sent" = {
            special_use = "\\Sent";
            auto = "subscribe";
          };
          "mailbox Junk" = {
            special_use = "\\Junk";
            auto = "subscribe";
          };
          "mailbox Trash" = {
            special_use = "\\Trash";
            auto = "subscribe";
          };
        };

        service = [
          {
            _section.name = "imap-login";
            # IMAP with implicit TLS (993) only.
            "inet_listener imap".port = 0;
          }
          {
            _section.name = "lmtp";
            "unix_listener ${private}/dovecot-lmtp" = {
              mode = "0600";
              user = "postfix";
              group = "postfix";
            };
          }
          {
            _section.name = "auth";
            "unix_listener ${private}/auth" = {
              mode = "0660";
              user = "postfix";
              group = "postfix";
            };
          }
        ];
      };
    };

    systemd.services = {
      postfix = {
        wants = [
          addressesUp
          "acme-${host}.service"
          "opendkim.service"
        ];
        after = [
          addressesUp
          "acme-${host}.service"
          "opendkim.service"
        ];
      };
      dovecot = {
        wants = [
          addressesUp
          "acme-${host}.service"
        ];
        after = [
          addressesUp
          "acme-${host}.service"
          "postfix-setup.service"
        ];
      };
    };
  };
}
