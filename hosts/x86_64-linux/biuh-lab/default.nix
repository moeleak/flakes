{
  config,
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
    guanranwang = {
      isNormalUser = true;
      shell = pkgs.fish;
    };
  };

  neovim = import ../../../programs/neovim.nix { inherit pkgs inputs; };
in
{
  imports = [
    ./hardware-configuration.nix
    ./frp.nix
    ../../../system/boot.nix
    ../../../system/nix.nix
    ../../../system/sops.nix
    ../../../system/virtualization/docker.nix
    ../../../system/network.nix
    ../../../programs/sing-box.nix
    ../../../programs/tmux.nix
    ../../../programs/shell.nix
    ../../../hardware/NV.nix
    ../../../zone/locale.nix
  ];

  networking = {
    hostName = "biuh-lab";
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
    variables.EDITOR = "nvim";
    systemPackages = with pkgs; [
      neovim
      gcc
      gnumake
      colmena
      wget
      fish
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
    ];
  };

  programs = {
    firefox.enable = true;
    direnv.enable = true;
    starship.enable = true;
    nix-ld.enable = true;
    fish = {
      shellInit = ''
        source ${pkgs.fish}/share/fish/completions/cargo.fish
      '';
      interactiveShellInit = ''
        set -g fish_greeting ""

        set -g fish_color_autosuggestion brblack
        set -g fish_color_cancel --reverse
        set -g fish_color_command 87afd7
        set -g fish_color_comment red
        set -g fish_color_cwd green
        set -g fish_color_cwd_root red
        set -g fish_color_end green
        set -g fish_color_error brred
        set -g fish_color_escape brcyan
        set -g fish_color_history_current --bold
        set -g fish_color_host normal
        set -g fish_color_host_remote yellow
        set -g fish_color_keyword normal
        set -g fish_color_match --background=brblue
        set -g fish_color_normal normal
        set -g fish_color_operator brcyan
        set -g fish_color_option cyan
        set -g fish_color_param cyan
        set -g fish_color_quote yellow
        set -g fish_color_redirection cyan --bold
        set -g fish_color_search_match bryellow --background=brblack
        set -g fish_color_selection white --bold --background=brblack
        set -g fish_color_status red
        set -g fish_color_user brgreen
        set -g fish_color_valid_path --underline

        set -g fish_pager_color_background normal
        set -g fish_pager_color_completion normal
        set -g fish_pager_color_description yellow --italics
        set -g fish_pager_color_prefix normal --bold --underline
        set -g fish_pager_color_progress brwhite --background=cyan
        set -g fish_pager_color_secondary_background normal
        set -g fish_pager_color_secondary_completion normal
        set -g fish_pager_color_secondary_description normal
        set -g fish_pager_color_secondary_prefix normal
        set -g fish_pager_color_selected_background --reverse
        set -g fish_pager_color_selected_completion normal
        set -g fish_pager_color_selected_description normal
        set -g fish_pager_color_selected_prefix normal

        set -g fish_key_bindings fish_default_key_bindings
      '';
    };
    git = {
      enable = true;
      config = {
        user.name = "MoeLeak";
        user.email = "i@leak.moe";
        alias = {
          st = "status";
          lg = "log --oneline --graph --all --decorate";
        };
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        pull.rebase = true;
      };
    };
  };

  services = {
    vscode-server = {
      enable = true;
      enableFHS = true;
    };

    openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };

    ollama = {
      enable = true;
      host = "0.0.0.0";
      package = pkgs.ollama-cuda;
    };

    btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = [ "/mnt/data" ];
    };

    samba = {
      enable = true;
      settings = {
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

  hardware.graphics.enable32Bit = true;
  hardware.nvidia-container-toolkit.enable = lib.mkForce true;

  security.unprivilegedUsernsClone = true;

  nix.settings.trusted-users = [
    "root"
    "moeleak"
    "guanranwang"
  ];

  system.stateVersion = "26.05";
}
