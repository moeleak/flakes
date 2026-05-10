{ lib, pkgs, ... }:

{
  programs.sway.enable = true;

  fonts.packages = lib.mkAfter [
    pkgs.nerd-fonts._0xproto
    pkgs.noto-fonts-cjk-sans
  ];

  home-manager.users.moeleak.programs.foot = {
    enable = true;
    package = pkgs.foot;
    settings = {
      main.font = "0xProto Nerd Font Mono:size=12";
    };
  };

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
        user = "greeter";
      };
    };
  };
}
