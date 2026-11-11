# Compilers, build tools and coding agents.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.packages.dev;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  options.my.packages.dev = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      home.packages = [
        pkgs.claude-code
        pkgs.claude-swap
        pkgs.codex
        pkgs.codex-auth
        pkgs.openspec
        pkgs.branchfs
        pkgs.workmux
        pkgs.android-tools

        pkgs.cargo
        pkgs.rustc
        pkgs.rustfmt

        pkgs.clang-tools
        pkgs.clang
        (lib.hiPrio pkgs.gcc16)
        pkgs.llvm
        pkgs.cmake
        pkgs.ccls
        pkgs.gnumake
      ]
      ++ lib.optionals isDarwin [
        pkgs.apple-sdk
      ];
    };
  };
}
