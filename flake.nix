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
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-licheepi4a,
      nix-darwin,
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

      lp4aSystem = "x86_64-linux";
      lp4aNixpkgs = import nixos-licheepi4a.inputs.nixpkgs {
        system = lp4aSystem;
      };
      lp4aColmenaNixpkgs = {
        inherit (lp4aNixpkgs)
          config
          lib
          overlays
          ;
        path = nixos-licheepi4a.inputs.nixpkgs.outPath;
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
            modules = [
              ./modules/nixos
              host
              { networking.hostName = name; }
            ];
          }
        )
        // {
          lp4a = nixos-licheepi4a.inputs.nixpkgs.lib.nixosSystem {
            system = lp4aSystem;
            specialArgs = lp4aSpecialArgs;
            modules = lp4aModules;
          };
        };

      colmena = {
        meta = {
          nixpkgs = lp4aColmenaNixpkgs;
          specialArgs = lp4aSpecialArgs;
        };

        lp4a =
          { ... }:
          {
            deployment.targetHost = "100.76.208.19";
            deployment.targetPort = 2333;
            deployment.targetUser = "root";
            imports = lp4aModules;
          };
      };

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
