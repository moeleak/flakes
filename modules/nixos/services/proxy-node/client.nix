# The sing-box profile a proxy user downloads: TUN, mainland China direct,
# everything else through the user's nodes. Needs sing-box 1.12 or later.
#
# With `tailscale`, the device also joins a tailnet (1.13 or later): its
# addresses, subnet routes and *.ts.net names go through Tailscale. The
# profile carries no auth key; sing-box logs a login URL on the first start,
# and Tailscale's own connections go through the proxy.
#
# With `lab`, the profile works like the flake's Lab clients (see
# modules/common/services/sing-box): all traffic but private addresses goes
# to the `egress` selector, whose default `lab` hands it to the Lab relay,
# which splits it itself. Names resolve to FakeIPs so Lab gets the domains.
# `egress` can also be `split` (this profile's own rules, through a local
# loopback), `proxy` or `direct`. The relay only answers on Lab's campus
# network.
#
# `secret` turns a sops secret name into a `_secret` reference, `nodes` lists the
# nodes this user may use.
{
  proxy,
  secret,
  user,
  nodes,
  tailscale ? false,
  lab ? false,
}:

let
  tag = node: node;
  optionals = cond: list: if cond then list else [ ];
  optionalAttrs = cond: attrs: if cond then attrs else { };

  # Where traffic goes once the rules below have not kept it local.
  internet = if lab then "egress" else "proxy";
  # `split` in `egress` re-enters the rules here, past the egress rule.
  splitPort = 1081;

  ruleSet = repo: name: {
    type = "remote";
    tag = name;
    format = "binary";
    url = "https://raw.githubusercontent.com/SagerNet/${repo}/rule-set/${name}.srs";
    http_client.detour = "proxy";
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
        detour = internet;
      }
      {
        type = "https";
        tag = "dns-cn";
        server = "223.5.5.5";
      }
    ]
    ++ optionals tailscale [
      {
        type = "tailscale";
        tag = "dns-tailscale";
        endpoint = "tailscale";
      }
    ]
    ++ optionals lab [
      {
        type = "fakeip";
        tag = "fakeip";
        inet4_range = "198.18.0.0/15";
      }
    ];
    rules =
      optionals tailscale [
        {
          domain_suffix = [ "ts.net" ];
          server = "dns-tailscale";
        }
      ]
      ++ optionals lab [
        {
          query_type = [
            "A"
            "AAAA"
          ];
          server = "fakeip";
        }
      ]
      ++ [
        {
          rule_set = [ "geosite-cn" ];
          server = "dns-cn";
        }
      ];
    final = "dns-remote";
    strategy = if lab then "ipv4_only" else "prefer_ipv4";
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
  ]
  ++ optionals lab [
    {
      type = "socks";
      tag = "split-in";
      listen = "127.0.0.1";
      listen_port = splitPort;
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
    server = proxy.nodes.${node}.host;
    server_port = proxy.vless.port;
    uuid = secret "sing-box-users/${user}/uuid";
    inherit (proxy.vless) flow;
    packet_encoding = "xudp";
    tls = {
      enabled = true;
      server_name = proxy.nodes.${node}.host;
    };
  }) nodes
  ++ optionals lab [
    {
      type = "selector";
      tag = "egress";
      outbounds = [
        "lab"
        "split"
        "proxy"
        "direct"
      ];
      default = "lab";
      interrupt_exist_connections = true;
    }
    {
      type = "shadowsocks";
      tag = "lab";
      server = proxy.lab.address;
      server_port = proxy.lab.port;
      method = "2022-blake3-aes-128-gcm";
      password = secret "sing-box-lab-password";
      connect_timeout = "5s";
      multiplex = {
        enabled = true;
        protocol = "smux";
        max_connections = 4;
        min_streams = 4;
      };
    }
    {
      type = "socks";
      tag = "split";
      server = "127.0.0.1";
      server_port = splitPort;
      inet4_bind_address = "127.0.0.1";
    }
  ]
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
    ]
    # Before the private ranges, which include Tailscale's IPv6 addresses.
    ++ optionals tailscale [
      {
        preferred_by = [ "tailscale" ];
        outbound = "tailscale";
      }
    ]
    ++ optionals lab [
      {
        ip_is_private = true;
        outbound = "direct";
      }
      {
        # The profile's own updates and the nodes.
        domain_suffix = [ proxy.domain ];
        outbound = "direct";
      }
      {
        # The campus learning portal, through Lab whatever egress is.
        domain_suffix = [ "learn.hibiuh.edu.cn" ];
        outbound = "lab";
      }
      {
        # Everything else goes to egress, except what split sends back.
        type = "logical";
        mode = "and";
        rules = [
          {
            network = [
              "tcp"
              "udp"
            ];
          }
          {
            inbound = [ "split-in" ];
            invert = true;
          }
        ];
        outbound = "egress";
      }
    ]
    ++ [
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
    ]
    ++ optionals lab [
      {
        inbound = [ "split-in" ];
        outbound = "proxy";
      }
    ];
    rule_set = [
      (ruleSet "sing-geosite" "geosite-cn")
      (ruleSet "sing-geoip" "geoip-cn")
    ];
    final = internet;
    auto_detect_interface = true;
    default_domain_resolver = "dns-cn";
  };

  experimental.cache_file = {
    enabled = true;
  }
  // optionalAttrs lab {
    # Keep the FakeIPs that applications cached valid across restarts.
    store_fakeip = true;
  };
}
// optionalAttrs tailscale {
  endpoints = [
    {
      type = "tailscale";
      tag = "tailscale";
      accept_routes = true;
      detour = "proxy";
    }
  ];
}
