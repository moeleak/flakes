# Serves each proxy user's client configuration by token; see main.go.
{ buildGoModule }:

buildGoModule {
  pname = "proxy-config";
  version = "0.3.0";
  src = ./.;
  vendorHash = "sha256-1OqyA5VZT2CE3qytUw8BmMPNjQ8xji4DTWh457j6MUM=";
  meta.mainProgram = "proxy-config";
}
