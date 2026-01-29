{ config, ... }:

let
  secret = name: {
    _secret = config.sops.secrets.${name}.path;
  };
in
{
  log = {
    level = "info";
  };

  experimental = {
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
        detour = "proxy";
      }

    ];

    rules = [
      {
        query_type = [
          "A"
          "AAAA"
        ];
        server = "fakeip";
      }
      {
        ip_accept_any = true;
        server = "dns-tailscale";
      }
      {
        domain_suffix = [ "ts.net" ];
        server = "dns-tailscale";
      }
      {
        rule_set = [ "gfwlist" ];
        server = "doh-proxy";
      }
      {
        rule_set = [ "geosite-cn" ];
        server = "doh-cn";
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
        server = "doh-proxy";
      };
    }
  ];
  inbounds = [
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
    {
      type = "direct";
      tag = "dns-in";
      listen = "127.0.0.1";
      listen_port = 53;
      network = "udp";
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
      ];
      default = "moeleak-lax";
    }
    {
      type = "direct";
      tag = "direct";
    }
    {
      type = "block";
      tag = "block";
    }
    {
      type = "vless";
      tag = "guanran-lax";
      server = secret "sing-box-guanran-lax0-server";
      server_port = 27253;
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
    }
    {
      type = "vless";
      tag = "guanran-tyo";
      server = secret "sing-box-guanran-tyo0-server";
      server_port = 27253;
      uuid = secret "sing-box-guanran-uuid";
      flow = "xtls-rprx-vision";
      tls = {
        enabled = true;
        server_name = secret "sing-box-guanran-tyo0-server";
        utls = {
          enabled = true;
          fingerprint = "chrome";
        };
      };
    }
    {
      domain_resolver = {
        server = "doh-cn";
        strategy = "prefer_ipv4";
      };
      flow = "xtls-rprx-vision";
      packet_encoding = "";
      server = secret "sing-box-moeleak-lax-server";
      server_port = 11451;
      tls = {
        enabled = true;
        insecure = false;
        reality = {
          enabled = true;
          public_key = secret "sing-box-moeleak-lax-public-key";
          short_id = secret "sing-box-moeleak-lax-short-id";
        };
        server_name = "www.microsoft.com";
        utls = {
          enabled = true;
          fingerprint = "chrome";
        };
      };
      uuid = secret "sing-box-moeleak-lax-uuid";
      tag = "moeleak-lax";
      type = "vless";
    }
  ];

  route = {
    default_domain_resolver = {
      server = "dns-google";
    };

    rule_set = [
      {
        type = "remote";
        tag = "geosite-cn";
        format = "binary";
        url = "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs";
        download_detour = "proxy";
      }
      {
        type = "remote";
        tag = "geoip-cn";
        format = "binary";
        url = "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs";
        download_detour = "proxy";
      }
      {
        type = "remote";
        tag = "gfwlist";
        format = "binary";
        url = "https://raw.githubusercontent.com/KaringX/karing-ruleset/sing/ACL4SSR/ProxyGFWlist.srs";
        download_detour = "proxy";
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
        domain_suffix = [
          "nixos.org"
        ];
        outbound = "proxy";
      }
      {
        domain_suffix = [
          "frp-mad.com"
          "lax.leak.moe"
          "szh.leak.moe"
          "hk.leak.moe"
        ];
        outbound = "direct";
      }
      {
        domain_suffix = [
          "ts.net"
        ];
        outbound = "tailscale-endpoint";
      }
      {
        ip_cidr = [
          "100.64.0.0/10"
        ];
        outbound = "tailscale-endpoint";
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

    final = "proxy";
    auto_detect_interface = true;
  };
}
