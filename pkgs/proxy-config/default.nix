# Serves each proxy user's client configuration by token; see main.go.
{ buildGoModule }:

buildGoModule {
  pname = "proxy-config";
  version = "0.1.0";
  src = ./.;
  vendorHash = null;
  meta.mainProgram = "proxy-config";
}
