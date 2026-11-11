# Modules that work on both NixOS and macOS. Each one declares an option under
# `my.*` and does nothing while that option is null.
{
  imports = import ../../lib/find-modules.nix ./.;
}
