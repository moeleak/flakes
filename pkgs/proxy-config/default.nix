# Serves each proxy user's client configuration by token; see main.go. The
# page's script, with its Material Web components, is bundled from web/.
{
  buildGoModule,
  buildNpmPackage,
  esbuild,
}:

let
  version = "0.4.0";

  web = buildNpmPackage {
    pname = "proxy-config-web";
    inherit version;
    src = ./web;
    npmDepsHash = "sha256-gQOwa7dGK+kgLdwfCr0msJc160iq0ehtqenGLlDLPYU=";
    nativeBuildInputs = [ esbuild ];
    dontNpmBuild = true;
    buildPhase = ''
      runHook preBuild
      esbuild page.js --bundle --minify --format=esm --target=es2021 --outfile=bundle.js
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm644 bundle.js $out/page.js
      runHook postInstall
    '';
  };
in
buildGoModule {
  pname = "proxy-config";
  inherit version;
  src = ./.;
  vendorHash = "sha256-1OqyA5VZT2CE3qytUw8BmMPNjQ8xji4DTWh457j6MUM=";
  passthru = { inherit web; };
  meta.mainProgram = "proxy-config";
}
