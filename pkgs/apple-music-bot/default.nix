# The Apple Music Telegram bot (the private moeleak/apple-music-downloader-bot,
# the flake input `apple-music-bot`), built as its Dockerfile does: the
# telegram bot command alone, without cgo.
{
  buildGoModule,
  src,
}:

buildGoModule {
  pname = "apple-music-bot";
  version = "0-unstable-2026-11-21";
  inherit src;

  vendorHash = "sha256-qFgnCIby2kr/SHI1mDZ63uOItozgwpLRhMprwg8405U=";
  subPackages = [ "cmd/apple-music-bot" ];
  env.CGO_ENABLED = "0";

  meta.mainProgram = "apple-music-bot";
}
