{
  description = "NixOS and macOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-5a07111.url = "github:nixos/nixpkgs/5a0711127cd8b916c3d3128f473388c8c79df0da";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    moevim.url = "github:moeleak/moevim";

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-licheepi4a.url = "github:ryan4yin/nixos-licheepi4a";

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
      nixpkgs-5a07111,
      home-manager,
      lanzaboote,
      nixos-licheepi4a,
      nix-darwin,
      sops-nix,
      ...
    }@inputs:
    let
      lp4aSystem = "x86_64-linux";
      lp4aSpecialArgs = {
        inherit inputs;
        nixpkgs = nixos-licheepi4a.inputs.nixpkgs;
        pkgsKernel = nixos-licheepi4a.packages.${lp4aSystem}.pkgsKernelCross;
      };
      lp4aModules = [
        {
          nixpkgs.crossSystem = {
            system = "riscv64-linux";
          };
        }
        (nixos-licheepi4a + "/modules/licheepi4a.nix")
        (nixos-licheepi4a + "/modules/sd-image/sd-image-lp4a.nix")
        ./hosts/riscv64-linux/lp4a
      ];
    in
    {
      overlays = {
        obs-bilibili-stream = import ./overlays/obs-bilibili-stream.nix;
      };

      nixosConfigurations = {
        "LoliIsland-PC-Nix" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/x86_64-linux/LoliIsland-PC-Nix
            ./system/nix.nix
            ./system/virtualization/docker.nix
            ./system/virtualization/winboat.nix
            ./system/network.nix
            ./system/bluetooth.nix
            ./system/packages.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.default
            lanzaboote.nixosModules.lanzaboote
            (
              { pkgs, lib, ... }:
              {
                environment.systemPackages = [ pkgs.sbctl ];
                boot.loader.systemd-boot.enable = lib.mkForce false;
                boot.lanzaboote = {
                  enable = true;
                  pkiBundle = "/var/lib/sbctl";
                };
              }
            )
            (
              { ... }:
              {
                nixpkgs.overlays = [ self.overlays.obs-bilibili-stream ];
              }
            )
          ];
        };

        "LoliIsland-Laptop-Nix" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/x86_64-linux/LoliIsland-Laptop-Nix
            ./system/nix.nix
            ./system/virtualization/docker.nix
            ./system/network.nix
            ./system/bluetooth.nix
            ./system/packages.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.default
            (
              { ... }:
              {
                nixpkgs.overlays = [ self.overlays.obs-bilibili-stream ];
              }
            )
          ];
        };

        lp4a = nixos-licheepi4a.inputs.nixpkgs.lib.nixosSystem {
          system = lp4aSystem;
          specialArgs = lp4aSpecialArgs;
          modules = lp4aModules;
        };
      };

      colmena = {
        meta = {
          nixpkgs = import nixos-licheepi4a.inputs.nixpkgs {
            system = lp4aSystem;
          };
          specialArgs = lp4aSpecialArgs;
        };

        lp4a = { ... }: {
          deployment.targetHost = "192.168.123.127";
          deployment.targetUser = "root";
          imports = lp4aModules;
        };
      };

      homeConfigurations =
        let
          username = "moeleak";
          system = "x86_64-linux";
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              self.overlays.obs-bilibili-stream
            ];
          };
          pkgs-5a07111 = import nixpkgs-5a07111 {
            stdenv.hostPlatform.system = system;
            config.allowUnfree = true;
            config.cudaSupport = true;
          };
        in
        {
          ${username} = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ ./home-manager/home.nix ];
            extraSpecialArgs = {
              inherit inputs;
              osConfig = { };
              pkgs-5a07111 = pkgs-5a07111;
              stdenv.hostPlatform.system = system;
            };
          };
        };

      darwinConfigurations = {
        "LoliIsland-Mac" = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/aarch64-darwin/LoliIsland-Mac
            sops-nix.darwinModules.sops
            home-manager.darwinModules.default
          ];
        };
      };
    };
}
