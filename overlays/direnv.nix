_final: _super: {
  direnv = _super.direnv.overrideAttrs (_: {
    doCheck = false;
  });
}
