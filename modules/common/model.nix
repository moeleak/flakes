{ lib, ... }:
{
  options.my = {
    # Decides which modules are on by default; a host can still set any
    # `my.*` option to `{ }` or `null` itself.
    variant = lib.mkOption {
      type = lib.types.enum [
        "minimal"
        "desktop"
        "server"
      ];
      default = "minimal";
    };

    # The human user of the host: owns the sops key and the Home Manager
    # configuration.
    user = lib.mkOption {
      type = lib.types.str;
      default = "moeleak";
    };
  };
}
