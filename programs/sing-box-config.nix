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
        domain_suffix = [
          "example.com"
          "example.net"
        ];
        server = "doh-proxy";
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
    strategy = "prefer_ipv4";
  };

  inbounds = [
    {
      type = "tun";
      tag = "tun-in";
      interface_name = "utun233";
      address = [ "172.19.0.1/30" ];
      mtu = 9000;
      auto_route = true;
      strict_route = true;
      stack = "system";
      sniff = true;
      sniff_override_destination = true;
    }
  ];

  outbounds = [
    {
      type = "selector";
      tag = "proxy";
      outbounds = [
        "lax0"
        "tyo0"
        "tyo1"
      ];
      default = "lax0";
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
      tag = "lax0";
      server = secret "sing-box-lax0-server";
      server_port = 27253;
      uuid = secret "sing-box-vless-uuid";
      flow = "xtls-rprx-vision";
      tls = {
        enabled = true;
        server_name = secret "sing-box-lax0-server";
        utls = {
          enabled = true;
          fingerprint = "chrome";
        };
      };
    }
    {
      type = "vless";
      tag = "tyo0";
      server = secret "sing-box-tyo0-server";
      server_port = 27253;
      uuid = secret "sing-box-vless-uuid";
      flow = "xtls-rprx-vision";
      tls = {
        enabled = true;
        server_name = secret "sing-box-tyo0-server";
        utls = {
          enabled = true;
          fingerprint = "chrome";
        };
      };
    }
    {
      type = "vless";
      tag = "tyo1";
      server = secret "sing-box-tyo1-server";
      server_port = 27253;
      uuid = secret "sing-box-vless-uuid";
      flow = "xtls-rprx-vision";
      tls = {
        enabled = true;
        server_name = secret "sing-box-tyo1-server";
        utls = {
          enabled = true;
          fingerprint = "chrome";
        };
      };
    }
  ];

  route = {
    default_domain_resolver = {
      server = "doh-cn";
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
        domain_suffix = [
          "example.com"
          "example.net"
        ];
        outbound = "proxy";
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
