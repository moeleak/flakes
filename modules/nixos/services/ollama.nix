{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.ollama;
in
{
  options.my.services.ollama = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    services.ollama = {
      enable = true;
      package = pkgs.ollama-cuda;
    };
  };
}
