{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  managedUsers = {
    moeleak = {
      isNormalUser = true;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      shell = pkgs.fish;
      home = "/home/moeleak";
    };
    kaggle = {
      isNormalUser = true;
      shell = pkgs.bash;
    };
    zifengdeng = {
      isNormalUser = true;
      shell = pkgs.bash;
    };
    junhaochen = {
      isNormalUser = true;
      shell = pkgs.bash;
    };
    guanranwang = {
      isNormalUser = true;
      shell = pkgs.fish;
    };
    ziyanxiao = {
      isNormalUser = true;
      extraGroups = [ "docker" ];
      shell = pkgs.fish;
    };
    cvpr = {
      isNormalUser = true;
      shell = pkgs.fish;
      packages = [ pkgs.claude-swap ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ43sOLJu4sxn0Fc1Rc+Z4eEBkcJborw6r/VpcpmSp5T alan@BlakeMacBook-Pro.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExZDkXsgLa31xUKC/9ZCNQrIiNyrE2rSUhnlfY/7rfU codex-chl66-20260602"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMz+2frjnWmRB86/XlWOaPLxSWnQRIAwf7x83v8xTaHw i@leak.moe"
      ];
    };
  };

in
{
  imports = [
    ./hardware-configuration.nix
    ./strata.nix
    inputs.vscode-server.nixosModules.default
  ];

  my = {
    variant = "server";
    hardware.nvidia.container32 = true;
    services.sing-box.lab = "server";
    services.frp = {
      serverAddr = "47.107.83.180";
      proxies = [
        {
          name = "proxy_20260730152817_1487ea8d"; # Velocity
          type = "tcp";
          localPort = 25500;
          remotePort = 25500;
        }
        {
          name = "proxy_20260730152749_959bdd81"; # Simple Voice Chat
          type = "udp";
          localPort = 11110;
          remotePort = 11110;
        }
        {
          name = "proxy_20260730152850_e569d851"; # Geyser
          type = "udp";
          localPort = 19132;
          remotePort = 19132;
        }
        {
          name = "proxy_20260926124929_42124625"; # SSH
          type = "tcp";
          localPort = 22;
          remotePort = 33387;
        }
      ];
    };
  };

  networking = {
    interfaces.eno1np0.ipv4.addresses = [
      {
        address = "10.90.0.3";
        prefixLength = 24;
      }
    ];
    defaultGateway = "10.90.0.1";
    nameservers = [
      "10.80.0.17"
      "10.80.0.18"
    ];
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelModules = [ "tcp_bbr" ];
    kernel.sysctl = {
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "vm.dirty_background_bytes" = 4294967296;
      "vm.dirty_bytes" = 17179869184;
      "vm.dirty_expire_centisecs" = 30000;
      "vm.dirty_writeback_centisecs" = 5000;
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
    tmp = {
      useTmpfs = true;
      tmpfsSize = "256G";
    };
  };

  users.users = managedUsers;

  environment = {
    systemPackages = with pkgs; [
      gcc
      gnumake
      colmena
      wget
      git
      btop-cuda
      fastfetch
      jdk25_headless
      rustc
      cargo
      rust-analyzer
      python314
      iotop
      codex
      claude-code
      devenv
      tree
      qemu
      vmtouch
      pi-coding-agent
    ];
  };

  programs.starship.enable = true;

  services = {
    vscode-server = {
      enable = true;
      enableFHS = true;
    };

    openssh = {
      enable = true;
      settings.PermitRootLogin = "prohibit-password";
    };

    ollama = {
      enable = true;
      host = "127.0.0.1";
      package = pkgs.ollama-cuda;
    };

    btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = [ "/" ];
    };

    samba = {
      enable = true;
      settings = {
        comfyui = {
          path = "/home/moeleak/Projects/comfyui-workspace";
          browseable = true;
          writable = true;
          guestOk = true;
          "force user" = "moeleak";
          "force group" = "users";
        };
        resources = {
          path = "/samba/resources";
          browseable = true;
          writable = false;
          guestOk = true;
        };
        mcm = {
          path = "/samba/mcm";
          browseable = true;
          writable = true;
          guestOk = true;
        };
      };
    };
  };

  # Bolt databases get badly fragmented under btrfs CoW + compression on this HDD,
  # making containerd miss dockerd's start timeout. NOCOW only applies to files
  # created afterwards; existing ones must be copied once to pick it up.
  systemd.tmpfiles.rules = [
    "h /var/lib/docker/containerd/daemon/io.containerd.metadata.v1.bolt - - - - +C"
    "h /var/lib/docker/buildkit - - - - +C"
    "h /var/lib/docker/network/files - - - - +C"
    "h /home/moeleak/.local/share/docker/containerd/daemon/io.containerd.metadata.v1.bolt - - - - +C"
  ];

  # containerd opens meta.db with NoFreelistSync, so bbolt walks every page through
  # MADV_RANDOM 4K faults. On a cold HDD that is thousands of seeks and overruns
  # dockerd's hardcoded 15s containerd start timeout; one sequential read avoids it.
  systemd.services.docker.preStart = ''
    cat /var/lib/docker/containerd/daemon/io.containerd.metadata.v1.bolt/meta.db > /dev/null 2>&1 || true
  '';

  hardware.graphics.enable32Bit = true;
  hardware.nvidia-container-toolkit.enable = lib.mkForce true;

  nix.settings.trusted-users = [
    "root"
    "moeleak"
    "guanranwang"
  ];

  system.stateVersion = "26.05";
}
