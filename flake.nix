{
  description = "NixOS and macOS configuration";

  inputs = {
    nixpkgs.url = "github:moeleak/nixpkgs/nixos-unstable";
    nixpkgs-licheepi4a.url = "github:moeleak/nixpkgs/nixos-licheepi4a-unstable";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vscode-server = {
      url = "github:moeleak/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:moeleak/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-licheepi4a = {
      url = "github:moeleak/nixos-licheepi4a/unstable-revy-linux-2026-05-23";
      inputs.nixpkgs.follows = "nixpkgs-licheepi4a";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The Apple Music bot that as3 runs (modules/nixos/services/apple-music):
    # a private repository, so fetching it takes SSH access to GitHub.
    apple-music-bot = {
      url = "git+ssh://git@github.com/moeleak/apple-music-downloader-bot";
      flake = false;
    };

    # The same version as nixpkgs' colmena CLI, which reads `colmenaHive`.
    colmena = {
      url = "github:nix-community/colmena/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.stable.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-licheepi4a,
      nix-darwin,
      colmena,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      specialArgs = { inherit inputs; };

      # Every directory in hosts/<system>/ is a host, named after the directory.
      # `mkHost` receives the host name and its directory.
      hostsIn =
        dir: mkHost:
        lib.mapAttrs (name: _: mkHost name (dir + "/${name}")) (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)
        );

      # A host in hosts/x86_64-linux, as both nixosConfigurations and colmena
      # build it.
      x86Modules = name: host: [
        ./modules/nixos
        host
        { networking.hostName = name; }
      ];

      # What lib.nixosSystem adds to nixos/lib/eval-config.nix, which colmena
      # calls itself: without it a node would differ from its
      # nixosConfiguration (version, revision, flake registry).
      nixosSystemModule = nixpkgs': {
        nixpkgs.flake.source = nixpkgs'.outPath;
        system.nixos = {
          versionSuffix = nixpkgs'.lib.trivial.versionSuffix;
          revision = nixpkgs'.lib.trivial.revisionWithDefault null;
        };
      };

      # Hosts in hosts/x86_64-linux that colmena deploys, as root over SSH
      # (my.programs.ssh pins their host keys); see the README.
      deployTargets = {
        # Port 2333, like the `as3` and `an4` aliases.
        LoliIsland-VPS-AS3 = {
          targetHost = "lax-as3.leak.moe";
          targetPort = 2333;
          tags = [ "vps" ];
        };
        LoliIsland-VPS-AN4 = {
          targetHost = "lax-an4.leak.moe";
          targetPort = 2333;
          tags = [ "vps" ];
        };
        # Over Tailscale. Lab builds its own system, and `colmena apply-local
        # --sudo` on Lab deploys it there.
        biuh-lab = {
          targetHost = "100.64.44.88";
          tags = [ "lab" ];
          buildOnTarget = true;
          allowLocalDeployment = true;
        };
      };

      lp4aSystem = "x86_64-linux";
      lp4aNixpkgs = import nixos-licheepi4a.inputs.nixpkgs {
        system = lp4aSystem;
      };
      lp4aSpecialArgs = {
        inherit inputs;
        nixpkgs = nixos-licheepi4a.inputs.nixpkgs;
        pkgsKernel = nixos-licheepi4a.packages.${lp4aSystem}.pkgsKernelCross;
      };
      lp4aModules = [
        ./modules/nixos
        ./hosts/riscv64-linux/lp4a
      ];
    in
    {
      overlays = {
        direnv = import ./overlays/direnv.nix;
        obs-bilibili-stream = import ./overlays/obs-bilibili-stream.nix;
      };

      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          pi-rescue = pkgs.runCommand "pi-rescue-tests" {
            nativeBuildInputs = [
              pkgs.nodejs
              pkgs.pi-coding-agent
            ];
            PI_RESCUE_TEST_PACKAGE = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo";
          } ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            node --test ${./modules/common/programs/pi/extensions/rescue}/tests/*.test.ts
            touch "$out"
          '';
        }
      );

      nixosConfigurations =
        hostsIn ./hosts/x86_64-linux (
          name: host:
          lib.nixosSystem {
            system = "x86_64-linux";
            inherit specialArgs;
            modules = x86Modules name host;
          }
        )
        // {
          lp4a = nixos-licheepi4a.inputs.nixpkgs.lib.nixosSystem {
            system = lp4aSystem;
            specialArgs = lp4aSpecialArgs;
            modules = lp4aModules;
          };
        };

      # `colmena apply --on @vps`, `--on @lab`; see the README.
      colmenaHive = colmena.lib.makeHive self.colmena;
      colmena = {
        meta = {
          nixpkgs = import nixpkgs { system = "x86_64-linux"; };
          inherit specialArgs;
          nodeNixpkgs.lp4a = lp4aNixpkgs;
          nodeSpecialArgs.lp4a = lp4aSpecialArgs;
        };

        lp4a = {
          deployment.targetHost = "100.76.208.19";
          deployment.targetPort = 2333;
          deployment.targetUser = "root";
          imports = lp4aModules ++ [ (nixosSystemModule nixos-licheepi4a.inputs.nixpkgs) ];
        };
      }
      // lib.mapAttrs (name: deployment: {
        deployment = {
          targetUser = "root";
        }
        // deployment;
        imports = x86Modules name (./hosts/x86_64-linux + "/${name}") ++ [ (nixosSystemModule nixpkgs) ];
      }) deployTargets;

      darwinConfigurations = hostsIn ./hosts/aarch64-darwin (
        name: host:
        nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          inherit specialArgs;
          modules = [
            ./modules/darwin
            host
            { networking.hostName = name; }
          ];
        }
      );
    };
}
