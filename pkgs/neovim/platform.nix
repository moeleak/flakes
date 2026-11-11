# Target-specific workarounds, kept out of the editor configuration.
pkgs:

let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv) buildPlatform hostPlatform;
  isCross = buildPlatform.system != hostPlatform.system;
  needsLp4aWorkarounds = isCross && hostPlatform.isRiscV64;
in
{
  clangdCommand = [
    "clangd"
  ]
  ++ lib.optionals hostPlatform.isDarwin [
    # Query the compiler for a consistent set of headers. This also stops
    # the Nix clang-tools wrapper from injecting libc++ headers into an
    # Apple SDK compile command, which breaks even std::string.
    # Apple compilers use clangd's built-in SDK discovery; querying them
    # would put SDK headers ahead of clangd's built-in headers.
    (
      "--query-driver="
      + lib.concatStringsSep "," (
        lib.concatMap
          (
            directory:
            map (compiler: "${directory}/${compiler}") [
              "clang"
              "clang++"
              "gcc"
              "g++"
              "cc"
              "c++"
            ]
          )
          [
            "/nix/store/*/bin"
            "/etc/profiles/per-user/*/bin"
            "/run/current-system/sw/bin"
          ]
      )
    )
  ];

  lualine =
    if isCross then
      pkgs.vimUtils.buildVimPlugin {
        pname = "lualine.nvim";
        inherit (pkgs.vimPlugins.lualine-nvim) version src;
      }
    else
      pkgs.vimPlugins.lualine-nvim;

  # nixfmt and rustfmt are unavailable when cross-compiling for lp4a.
  formatterCommands =
    if needsLp4aWorkarounds then
      { nix = "alejandra"; }
    else
      {
        nix = "nixfmt";
        rust = "rustfmt";
      };
}
