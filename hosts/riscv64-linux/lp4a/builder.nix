{ pkgs, ... }:

let
  nixCrossRiscv64 = pkgs.writeShellApplication {
    name = "nix-cross-riscv64";
    text = ''
      usage() {
        printf '%s\n' \
          'usage: nix-cross-riscv64 <build|shell|run> <nixpkgs-attr> [nix args...]' \
          "" \
          'examples:' \
          '  nix-cross-riscv64 build btop -L' \
          '  nix-cross-riscv64 shell nixpkgs#hello' >&2
      }

      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi

      command="$1"
      attr="$2"
      shift 2

      case "$command" in
        build|shell|run) ;;
        *)
          usage
          exit 2
          ;;
      esac

      attr="''${attr#nixpkgs#}"
      attr="''${attr#\#}"

      expr="
        let
          nixpkgs = builtins.getFlake \"nixpkgs\";
          pkgs = import nixpkgs {
            localSystem = { system = \"x86_64-linux\"; };
            crossSystem = { system = \"riscv64-linux\"; };
            config.allowUnfree = true;
          };
        in
          pkgs.''${attr}
      "

      exec nix "$command" --impure --expr "$expr" "$@"
    '';
  };
in
{
  environment.systemPackages = [ nixCrossRiscv64 ];

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "100.64.44.88";
        protocol = "ssh-ng";
        sshUser = "moeleak";
        sshKey = "/home/moeleak/.ssh/id_ed25519";
        systems = [ "x86_64-linux" ];
        maxJobs = 8;
        speedFactor = 2;
      }
    ];
  };
}
