{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.llama;
in
{
  options.my.programs.llama = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    environment.systemPackages = with pkgs; [
      (pkgs.llama-cpp.override { cudaSupport = true; })
    ];
  };
}
