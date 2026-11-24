# The VMs this host runs: modules/nixos/services/vms/<hostName>/<name>.nix,
# one file each (lib/vms.nix). Each is a QEMU/KVM guest, vm-<name>.service,
# booted from a copy of its cloud image (images.nix), set up by cloud-init
# from a NoCloud seed that this module writes.
#
# The VMs sit on the bridge vmbr0, each on its tap vm-<name>, with this host
# as their gateway and resolver. Their traffic goes through sing-box here,
# whose TUN takes in what passes through the host as well: sing-box resolves
# for them (FakeIPs), and routes them as it routes the host, but with the VM's
# `egress` as the proxy (modules/common/services/sing-box). What it leaves
# alone (the campus network, 10.0.0.0/8) leaves masqueraded, out of
# `my.services.vms.uplink`; not into the TUN, where sing-box tells the VMs
# apart by their addresses.
#
# A VM with `dn42` is a node on DN42 (lib/dn42.nix) as Lab is: WireGuard to
# an4 and as3, which sing-box here takes over VLESS by the VM's address and
# the tunnel's port (before Lab's own rules, which match the port alone: the
# same port leads to different nodes for each), and BIRD, configured as the
# NixOS nodes are (lib/dn42-node.nix). Its WireGuard key is
# `dn42-wireguard/<name>` in secrets/dn42.yaml, which goes into the seed
# when the VM starts.
#
# The disk, /var/lib/vms/<name>/disk.qcow2, is made once, as a copy of the
# image resized to `disk`; cloud-init grows the root filesystem. A change of
# the seed (the definition, the BIRD configuration) gives cloud-init a new
# instance-id, and it runs again on the VM's next start; the host keys stay.
# A deploy never restarts a VM: `systemctl restart vm-<name>` does, shutting
# it down through ACPI first. `vm-console <name>` attaches to its serial
# console (Ctrl-] to leave).
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  vmLib = import ../../../../lib/vms.nix;
  inherit (vmLib) bridge;
  dn42 = import ../../../../lib/dn42.nix;
  images = import ./images.nix { inherit (pkgs) fetchurl; };

  vms = lib.filterAttrs (_: vm: vm.host == config.networking.hostName) vmLib.vms;

  tap = name: "vm-${name}";
  stateDir = name: "/var/lib/vms/${name}";
  runDir = name: "/run/vm-${name}";
  hex2 = n: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString n));
  mac = vm: "52:54:00:35:07:${hex2 vm.id}";

  # What the seed holds: cloud-init's meta-data, network-config and
  # user-data. In user-data, @WIREGUARD_KEY@ stands for the WireGuard key,
  # which the unit fills in.
  seedFor =
    name: vm:
    let
      isNode = vm.dn42 != null;
      nodeLib = import ../../../../lib/dn42-node.nix {
        inherit lib name;
        rtr = false;
      };
      node = dn42.nodes.${name};

      # The node's networkd files, as modules/nixos/services/dn42 has them.
      networkd = {
        "/etc/systemd/network/60-dn42.netdev" = ''
          [NetDev]
          Kind=dummy
          Name=dn42
        '';
        "/etc/systemd/network/60-dn42.network" = ''
          [Match]
          Name=dn42

          [Link]
          RequiredForOnline=no

          [Network]
          Address=${node.ipv4}/32
          Address=${node.ipv6}/128
          LinkLocalAddressing=no
        '';
      }
      // lib.concatMapAttrs (other: tunnel: {
        "/etc/systemd/network/60-${nodeLib.interface other}.netdev" = ''
          [NetDev]
          Kind=wireguard
          Name=${nodeLib.interface other}

          [WireGuard]
          PrivateKeyFile=/etc/wireguard/dn42.key
          ListenPort=${toString tunnel.port}

          [WireGuardPeer]
          PublicKey=${tunnel.publicKey}
          AllowedIPs=0.0.0.0/0
          AllowedIPs=::/0
          ${lib.optionalString (tunnel.endpoint != null) ''
            Endpoint=${tunnel.endpoint}
            PersistentKeepalive=25
          ''}
        '';
        # DN42's names go to its anycast resolver, through the tunnels.
        "/etc/systemd/network/60-${nodeLib.interface other}.network" = ''
          [Match]
          Name=${nodeLib.interface other}

          [Link]
          RequiredForOnline=no

          [Network]
          Address=${tunnel.localLinkLocal}/64
          LinkLocalAddressing=no
          IPv6AcceptRA=no
          IPv4ReversePathFilter=no
          DNS=172.20.0.53
          DNS=fd42:d42:d42:53::1
          Domains=~dn42 ~20.172.in-addr.arpa ~21.172.in-addr.arpa ~22.172.in-addr.arpa ~23.172.in-addr.arpa ~d.f.ip6.arpa
        '';
      }) nodeLib.tunnels;

      file =
        path: content: extra:
        {
          inherit path content;
          defer = true;
        }
        // extra;

      userData = {
        hostname = name;
        fqdn = if isNode then "${name}.${dn42.domain}" else name;
        # root alone, by its keys.
        users = [ ];
        disable_root = false;
        ssh_pwauth = false;
        ssh_authorized_keys = vm.authorizedKeys;
        # A new instance-id keeps the host's identity.
        ssh_deletekeys = false;
        package_update = true;
        packages = [
          "systemd-resolved"
        ]
        ++ lib.optionals isNode [
          "bird2"
          "wireguard-tools"
        ];
        write_files = [
          # The tunnels' endpoints resolve to sing-box's FakeIPs here, IPv6
          # ones among them, which the VM has no route to.
          {
            path = "/etc/gai.conf";
            content = ''
              precedence ::ffff:0:0/96 100
            '';
          }
        ]
        ++ lib.optionals isNode (
          lib.mapAttrsToList (path: content: file path content { }) networkd
          ++ [
            (file "/etc/wireguard/dn42.key" "@WIREGUARD_KEY@\n" {
              owner = "root:systemd-network";
              permissions = "0640";
            })
            (file "/etc/bird/bird.conf" nodeLib.birdConfig {
              owner = "bird:bird";
              permissions = "0640";
            })
          ]
        );
        runcmd = [
          [
            "systemctl"
            "enable"
            "--now"
            "systemd-resolved"
          ]
        ]
        ++ lib.optionals isNode [
          [
            "systemctl"
            "restart"
            "systemd-networkd"
          ]
          [
            "systemctl"
            "enable"
            "bird"
          ]
          [
            "systemctl"
            "restart"
            "bird"
          ]
        ];
      };

      networkConfig = {
        version = 2;
        ethernets.eth0 = {
          match.macaddress = mac vm;
          set-name = "eth0";
          addresses = [ "${vm.address}/${toString bridge.length}" ];
          routes = [
            {
              to = "default";
              via = bridge.address;
            }
          ];
          nameservers.addresses = [ bridge.address ];
        };
      };

      userDataFile = pkgs.writeText "user-data" ("#cloud-config\n" + builtins.toJSON userData);
      networkConfigFile = pkgs.writeText "network-config" (builtins.toJSON networkConfig);
      instanceId = builtins.substring 0 16 (
        builtins.hashString "sha256" (
          builtins.toJSON [
            userData
            networkConfig
          ]
        )
      );
      metaDataFile = pkgs.writeText "meta-data" (
        builtins.toJSON {
          instance-id = "${name}-${instanceId}";
          local-hostname = name;
        }
      );
    in
    pkgs.runCommand "vm-${name}-seed" { } ''
      mkdir $out
      cp ${userDataFile} $out/user-data
      cp ${networkConfigFile} $out/network-config
      cp ${metaDataFile} $out/meta-data
    '';

  qmp = name: command: ''
    printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"${command}"}' \
      | ${lib.getExe pkgs.socat} - UNIX-CONNECT:${runDir name}/qmp.sock >/dev/null || true
  '';

  vmService =
    name: vm:
    let
      seed = seedFor name vm;
      wireguardKey = config.sops.secrets."dn42-wireguard/${name}".path;
      device = "sys-subsystem-net-devices-${utils.escapeSystemdPath (tap name)}.device";
    in
    {
      description = "VM ${name}";
      wantedBy = [ "multi-user.target" ];
      requires = [ device ];
      after = [
        device
        "network.target"
      ];
      # Never by a deploy; see the top.
      restartIfChanged = false;
      path = [
        pkgs.qemu_kvm
        pkgs.xorriso
        pkgs.gnused
        pkgs.coreutils
      ];
      preStart = ''
        set -eu
        cd ${stateDir name}
        if [ ! -e disk.qcow2 ]; then
          qemu-img convert -p -O qcow2 ${images.${vm.image}} disk.qcow2.tmp
          qemu-img resize disk.qcow2.tmp ${toString vm.disk}G
          mv disk.qcow2.tmp disk.qcow2
        fi

        cd ${runDir name}
        rm -rf seed seed.iso
        mkdir seed
        cp ${seed}/* seed/
        chmod -R u+w seed
        ${lib.optionalString (vm.dn42 != null) ''
          key=$(cat ${wireguardKey})
          sed -i "s|@WIREGUARD_KEY@|$key|" seed/user-data
        ''}
        xorriso -as mkisofs -quiet -output seed.iso -volid cidata -joliet -rock seed
        rm -rf seed
      '';
      script = ''
        exec qemu-system-x86_64 \
          -name ${name} \
          -machine q35,accel=kvm \
          -cpu host \
          -smp ${toString vm.cores} \
          -m ${toString vm.memory}G \
          -nodefaults -no-user-config -display none \
          -drive file=${stateDir name}/disk.qcow2,if=none,id=disk,format=qcow2,cache=none,aio=native,discard=unmap \
          -device virtio-blk-pci,drive=disk,bootindex=1 \
          -drive file=${runDir name}/seed.iso,if=none,id=seed,format=raw,readonly=on \
          -device virtio-blk-pci,drive=seed \
          -netdev tap,id=net,ifname=${tap name},script=no,downscript=no,vhost=on \
          -device virtio-net-pci,netdev=net,mac=${mac vm} \
          -device virtio-rng-pci \
          -chardev socket,id=console,path=${runDir name}/console.sock,server=on,wait=off \
          -serial chardev:console \
          -qmp unix:${runDir name}/qmp.sock,server=on,wait=off
      '';
      # ACPI's power button, then the time the guest has to shut down.
      preStop = ''
        ${qmp name "system_powerdown"}
        while kill -0 "$MAINPID" 2>/dev/null; do sleep 1; done
      '';
      serviceConfig = {
        User = "vm";
        Group = "vm";
        SupplementaryGroups = [ "kvm" ];
        RuntimeDirectory = "vm-${name}";
        RuntimeDirectoryMode = "0700";
        TimeoutStartSec = "30min";
        TimeoutStopSec = 180;
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
in
{
  # The interface to the host's own network.
  options.my.services.vms.uplink = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
  };

  config = lib.mkIf (vms != { }) {
    assertions = [
      {
        assertion = config.my.services.vms.uplink != null;
        message = "vms: ${config.networking.hostName} runs VMs, but has no my.services.vms.uplink.";
      }
    ]
    ++ lib.flatten (
      lib.mapAttrsToList (name: vm: [
        {
          assertion = lib.stringLength name <= 10;
          message = "vms: the name ${name} is longer than 10 characters.";
        }
        {
          assertion = vm.authorizedKeys != [ ];
          message = "vms: ${name} has no authorizedKeys, and root logs in by them alone.";
        }
        {
          assertion = images ? ${vm.image};
          message = "vms: ${name}'s image ${vm.image} is not in images.nix.";
        }
        {
          assertion = vm.id >= 2 && vm.id <= 60;
          message = "vms: ${name}'s id ${toString vm.id} is outside 2–60 (the bridge, DN42's /26).";
        }
        {
          assertion =
            lib.length (lib.filter (other: other.id == vm.id) (lib.attrValues vmLib.vms)) == 1
            && lib.all (node: node.id != vm.id || (node.vm or null) == vm.host) (lib.attrValues dn42.nodes);
          message = "vms: ${name}'s id ${toString vm.id} is another VM's or node's.";
        }
      ]) vms
    );

    users.users.vm = {
      isSystemUser = true;
      group = "vm";
      extraGroups = [ "kvm" ];
    };
    users.groups.vm = { };

    sops.secrets = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "dn42-wireguard/${name}" {
        owner = "vm";
        group = "vm";
        mode = "0400";
      }
    ) (lib.filterAttrs (_: vm: vm.dn42 != null) vms);

    # NOCOW: the disks are large images rewritten in place, on btrfs.
    systemd.tmpfiles.rules = [
      "d /var/lib/vms 0750 vm vm -"
      "h /var/lib/vms - - - - +C"
    ]
    ++ lib.mapAttrsToList (name: _: "d ${stateDir name} 0750 vm vm -") vms;

    systemd.network = {
      enable = true;
      netdevs = {
        "50-${bridge.name}".netdevConfig = {
          Kind = "bridge";
          Name = bridge.name;
        };
      }
      // lib.mapAttrs' (
        name: _:
        lib.nameValuePair "50-${tap name}" {
          netdevConfig = {
            Kind = "tap";
            Name = tap name;
          };
          tapConfig = {
            User = "vm";
            Group = "vm";
            VNetHeader = true;
          };
        }
      ) vms;
      networks = {
        "50-${bridge.name}" = {
          matchConfig.Name = bridge.name;
          address = [ "${bridge.address}/${toString bridge.length}" ];
          networkConfig = {
            ConfigureWithoutCarrier = true;
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
          };
          linkConfig.RequiredForOnline = "no";
        };
      }
      // lib.mapAttrs' (
        name: _:
        lib.nameValuePair "50-${tap name}" {
          matchConfig.Name = tap name;
          networkConfig.Bridge = bridge.name;
          linkConfig.RequiredForOnline = "no";
        }
      ) vms;
    };
    networking.networkmanager.unmanaged = [
      "interface-name:${bridge.name}"
      "interface-name:vm-*"
    ];

    # What sing-box leaves alone leaves as the host.
    networking.nat = {
      enable = true;
      internalIPs = [ bridge.subnet ];
      externalInterface = config.my.services.vms.uplink;
    };

    # sing-box listens on the bridge's address, which networkd may not have
    # set yet when it starts: it must start anyway, as Lab's Tailscale is in it.
    boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

    services.sing-box.settings = {
      # The VMs' resolver; sing-box's own rules answer (hijack-dns).
      inbounds = [
        {
          type = "direct";
          tag = "vm-dns-in";
          listen = bridge.address;
          listen_port = 53;
          network = "udp";
        }
      ];
      # Each VM's tunnels, by its address and their port, to the node they
      # lead to, before Lab's own (modules/nixos/services/dn42).
      route.rules = lib.mkOrder 400 (
        lib.concatLists (
          lib.mapAttrsToList (
            name: vm:
            lib.mapAttrsToList (other: tunnel: {
              source_ip_cidr = [ "${vm.address}/32" ];
              network = "udp";
              inherit (tunnel) port;
              outbound = other;
            }) (import ../../../../lib/dn42-node.nix { inherit lib name; }).others
          ) (lib.filterAttrs (_: vm: vm.dn42 != null) vms)
        )
      );
    };

    systemd.services = lib.mapAttrs' (name: vm: lib.nameValuePair "vm-${name}" (vmService name vm)) vms;

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "vm-console" ''
        exec ${lib.getExe pkgs.socat} -,raw,echo=0,escape=0x1d UNIX-CONNECT:${runDir "$1"}/console.sock
      '')
    ];
  };
}
