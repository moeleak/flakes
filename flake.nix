{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-5a07111.url = "github:nixos/nixpkgs/5a0711127cd8b916c3d3128f473388c8c79df0da";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    nvix.url = "github:moeleak/nvix";
    khanelivim.url = "github:moeleak/khanelivim";
    go-musicfox.url = "github:go-musicfox/go-musicfox";
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-5a07111,
      home-manager,
      ...
    }@inputs:
    {
      nixosConfigurations = {
        "LoliIsland-PC-Nix" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/x86_64_linux/LoliIsland-PC-Nix
            ./system/nix.nix
            ./system/network.nix
            ./system/bluetooth.nix
            ./system/users.nix
            ./system/packages.nix
            home-manager.nixosModules.default
          ];
        };
      };
    };
}
