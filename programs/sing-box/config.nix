{
  config,
  lib,
  pkgs,
  ...
}:

let
  isLabServer = config.networking.hostName == "biuh-lab";
  isLabClient = config.networking.hostName == "LoliIsland-Mac";
  internetOutbound = if isLabClient then "egress" else "proxy";
  labAddress = "10.90.0.3";
  labPort = 8388;

  secret = name: {
    _secret = config.sops.secrets.${name}.path;
  };

  moeleak = {
    type = "vless";
    flow = "xtls-rprx-vision";
    packet_encoding = "";
    server_port = 11451;
    uuid = secret "sing-box-moeleak-uuid";

    tls = {
      enabled = true;
      insecure = false;
      server_name = "www.samsung.com";

      reality = {
        enabled = true;
        public_key = secret "sing-box-moeleak-public-key";
        short_id = secret "sing-box-moeleak-short-id";
      };

      utls = {
        enabled = true;
        fingerprint = "chrome";
      };
    };
  };
  guanran = {
    type = "vless";
    tag = "guanran-lax";
    server_port = 27253;
    domain_resolver = "doh-cn";
    uuid = secret "sing-box-guanran-uuid";
    flow = "xtls-rprx-vision";
    tls = {
      enabled = true;
      server_name = secret "sing-box-guanran-lax0-server";
      utls = {
        enabled = true;
        fingerprint = "chrome";
      };
    };
  };

  mk =
    base: tag: serverName:
    base
    // {
      inherit tag;
      server = secret serverName;
    };

in
{
  log = {
    level = "info";
  };

  experimental = {
    clash_api = {
      external_controller = "localhost:9090";
      external_ui = "ui";
      external_ui_download_url = "https://github.com/MetaCubeX/Yacd-meta/archive/gh-pages.zip";
      external_ui_download_detour = internetOutbound;
    };
    cache_file = {
      enabled = true;
    };
  };

  dns = {
    servers = [
      {
        type = "local";
        tag = "dns-local";
      }
      {
        type = "tailscale";
        tag = "dns-tailscale";
        endpoint = "tailscale-endpoint";
        accept_search_domain = true;
      }
      {
        type = "fakeip";
        tag = "fakeip";
        inet4_range = "198.18.0.0/15";
        # inet6_range = "fc00::/18";
      }
      {
        type = "tcp";
        server = "8.8.8.8";
        server_port = 53;
        tag = "dns-google";
      }
      {
        type = "https";
        tag = "doh-cn";
        server = "223.5.5.5";
        server_port = 443;
        path = "/dns-query";
        headers = {
          Host = "dns.alidns.com";
        };
        tls = {
          enabled = true;
          server_name = "dns.alidns.com";
        };
      }
      {
        type = "https";
        tag = "doh-proxy";
        server = "1.1.1.1";
        server_port = 443;
        path = "/dns-query";
        headers = {
          Host = "cloudflare-dns.com";
        };
        tls = {
          enabled = true;
          server_name = "cloudflare-dns.com";
        };
        detour = internetOutbound;
      }

    ];

    rules = [
      {
        preferred_by = "dns-tailscale";
        action = "route";
        server = "dns-tailscale";
      }
    ]
    ++ lib.optionals isLabServer [
      {
        inbound = [ "lab-in" ];
        rule_set = [ "geosite-cn" ];
        server = "doh-cn";
      }
      {
        # Remote clients must never receive this server's private FakeIP mapping.
        inbound = [ "lab-in" ];
        server = "doh-proxy";
      }
    ]
    ++ [
      {
        query_type = [
          "A"
          "AAAA"
        ];
        server = "fakeip";
      }
      {
        rule_set = [ "gfwlist" ];
        server = "doh-proxy";
      }
      {
        rule_set = [ "geosite-cn" ];
        server = if isLabClient then "doh-proxy" else "doh-cn";
      }
    ];

    final = "doh-proxy";
    strategy = "ipv4_only";
  };

  endpoints = [
    {
      type = "tailscale";
      tag = "tailscale-endpoint";
      auth_key = "";
      hostname = config.networking.hostName;
      domain_resolver = {
        # Keep Tailscale available when the Lab relay is unavailable.
        server = if isLabClient then "doh-cn" else "doh-proxy";
      };
    }
  ];
  inbounds = [
    (
      {
        type = "tun";
        tag = "tun-in";
        address = [
          "172.19.0.1/30"
          # "fdfe:dcba:9876::1/126"
        ];
        mtu = 9000;
        auto_route = true;
        strict_route = true;
        stack = "system";
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        auto_redirect = true;
      }
    )
    {
      type = "direct";
      tag = "dns-in";
      listen = "127.0.0.1";
      listen_port = 53;
      network = "udp";
    }
  ]
  ++ lib.optionals isLabServer [
    {
      type = "shadowsocks";
      tag = "lab-in";
      listen = labAddress;
      listen_port = labPort;
      method = "2022-blake3-aes-128-gcm";
      password = secret "sing-box-lab-password";
      multiplex.enabled = true;
    }
  ];

  outbounds = [
    {
      type = "selector";
      tag = "proxy";
      outbounds = [
        "guanran-lax"
        "guanran-tyo"
        "moeleak-lax"
        "moeleak-as3"
        "direct"
      ];
      default = "moeleak-lax";
    }
    {
      type = "direct";
      tag = "direct";
      domain_resolver = {
        server = "doh-cn";
        strategy = "ipv4_only";
      };
    }
    {
      type = "block";
      tag = "block";
    }

    (mk guanran "guanran-lax" "sing-box-guanran-lax0-server")
    (mk guanran "guanran-tyo" "sing-box-guanran-tyo0-server")
    (mk moeleak "moeleak-lax" "sing-box-moeleak-lax-server")
    (mk moeleak "moeleak-as3" "sing-box-moeleak-as3-server")
  ]
  ++ lib.optionals isLabClient [
    {
      type = "selector";
      tag = "egress";
      outbounds = [
        "lab"
        "proxy"
        "direct"
      ];
      default = "lab";
      interrupt_exist_connections = true;
    }
    {
      type = "shadowsocks";
      tag = "lab";
      server = labAddress;
      server_port = labPort;
      method = "2022-blake3-aes-128-gcm";
      password = secret "sing-box-lab-password";
      # auto_detect_interface dials this IP on the physical network, outside TUN.
      connect_timeout = "5s";
      multiplex = {
        enabled = true;
        protocol = "smux";
        max_connections = 4;
        min_streams = 4;
      };
    }
  ];

  route = {
    default_domain_resolver = {
      server = "doh-proxy";
    };

    rule_set = [
      {
        type = "remote";
        tag = "geosite-cn";
        format = "binary";
        url = "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs";
        http_client.detour = internetOutbound;
      }
      {
        type = "remote";
        tag = "geoip-cn";
        format = "binary";
        url = "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs";
        http_client.detour = internetOutbound;
      }
      {
        type = "remote";
        tag = "gfwlist";
        format = "binary";
        url = "https://raw.githubusercontent.com/KaringX/karing-ruleset/sing/ACL4SSR/ProxyGFWlist.srs";
        http_client.detour = internetOutbound;
      }
    ];

    rules = [
      {
        action = "sniff";
      }
      {
        protocol = "dns";
        action = "hijack-dns";
      }
      {
        network = "icmp";
        domain_regex = [ ".+" ];
        action = "resolve";
      }
      {
        preferred_by = [ "tailscale-endpoint" ];
        action = "route";
        outbound = "tailscale-endpoint";
      }
      {
        network = "icmp";
        action = "route";
        outbound = "direct";
      }
    ]
    ++ lib.optionals isLabClient [
      {
        ip_is_private = true;
        outbound = "direct";
      }
      {
        # Tailscale's control plane must not depend on the Lab relay.
        domain_suffix = [
          "leak.moe"
          "ts.cherr.cc"
        ];
        outbound = "direct";
      }
      {
        process_name = [ "cs2.exe" ];
        outbound = "direct";
      }
      {
        # Both domestic and international public TCP/UDP use this selector.
        network = [
          "tcp"
          "udp"
        ];
        outbound = "egress";
      }
    ]
    ++ [
      {
        domain_suffix = [
          "nixos.org"
          "updates.cdn-apple.com"
          "learn.hibiuh.edu.cn"
        ];
        outbound = "proxy";
      }
      {
        domain_suffix = [
          "leak.moe"
          "ts.cherr.cc"
          "office365.com"
        ];
        outbound = "direct";
      }
      {
        rule_set = [ "gfwlist" ];
        outbound = "proxy";
      }
      {
        ip_is_private = true;
        outbound = "direct";
      }
      {
        ip_cidr = [
          "103.97.201.87"
          "131.143.240.18"
        ];
        outbound = "direct";
      }
      {
        rule_set = [ "geosite-cn" ];
        outbound = "direct";
      }
      {
        rule_set = [ "geoip-cn" ];
        outbound = "direct";
      }
    ];

    final = internetOutbound;
    auto_detect_interface = true;
  };
}
