# The sing-box profile a proxy user downloads: TUN, mainland China direct,
# everything else through the user's nodes. Needs sing-box 1.12 or later.
#
# `secret` turns a sops secret name into a `_secret` reference, `nodes` lists the
# nodes this user may use.
{
  proxy,
  secret,
  user,
  nodes,
}:

let
  tag = node: node;

  ruleSet = repo: name: {
    type = "remote";
    tag = name;
    format = "binary";
    url = "https://raw.githubusercontent.com/SagerNet/${repo}/rule-set/${name}.srs";
    # Downloaded through the default outbound (route.final).
  };
in
{
  log.level = "warn";

  dns = {
    servers = [
      {
        type = "https";
        tag = "dns-remote";
        server = "1.1.1.1";
        detour = "proxy";
      }
      {
        type = "https";
        tag = "dns-cn";
        server = "223.5.5.5";
      }
    ];
    rules = [
      {
        rule_set = [ "geosite-cn" ];
        server = "dns-cn";
      }
    ];
    final = "dns-remote";
    strategy = "prefer_ipv4";
  };

  inbounds = [
    {
      type = "tun";
      tag = "tun-in";
      address = [
        "172.19.0.1/30"
        "fdfe:dcba:9876::1/126"
      ];
      auto_route = true;
      strict_route = true;
    }
  ];

  outbounds = [
    {
      type = "selector";
      tag = "proxy";
      outbounds = [ "auto" ] ++ map tag nodes;
      default = "auto";
    }
    {
      type = "urltest";
      tag = "auto";
      outbounds = map tag nodes;
    }
  ]
  ++ map (node: {
    type = "vless";
    tag = tag node;
    server = "${node}.${proxy.domain}";
    server_port = proxy.vless.port;
    uuid = secret "sing-box-users/${user}/uuid";
    inherit (proxy.vless) flow;
    packet_encoding = "xudp";
    tls = {
      enabled = true;
      server_name = "${node}.${proxy.domain}";
      utls = {
        enabled = true;
        fingerprint = "chrome";
      };
    };
  }) nodes
  ++ [
    {
      type = "direct";
      tag = "direct";
    }
  ];

  route = {
    rules = [
      { action = "sniff"; }
      {
        protocol = "dns";
        action = "hijack-dns";
      }
      {
        ip_is_private = true;
        outbound = "direct";
      }
      {
        rule_set = [
          "geosite-cn"
          "geoip-cn"
        ];
        outbound = "direct";
      }
    ];
    rule_set = [
      (ruleSet "sing-geosite" "geosite-cn")
      (ruleSet "sing-geoip" "geoip-cn")
    ];
    final = "proxy";
    auto_detect_interface = true;
    default_domain_resolver = "dns-cn";
  };

  experimental.cache_file.enabled = true;
}
