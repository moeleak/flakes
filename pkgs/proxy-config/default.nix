# Serves each proxy user's client configuration by token; see main.go. The
# page's script, with its Material Web components, is bundled from web/, and
# Material's type scale is exported as CSS for the server to inline.
{
  buildGoModule,
  buildNpmPackage,
  esbuild,
}:

let
  version = "0.4.1";

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
      node --input-type=module -e "
        const { styles } = await import('@material/web/typography/md-typescale-styles.js');
        process.stdout.write(styles.cssText);
      " > typescale.css
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm644 bundle.js $out/page.js
      install -Dm644 typescale.css $out/typescale.css
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
