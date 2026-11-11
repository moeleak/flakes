{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.git;
in
{
  options.my.programs.git = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      programs.git = {
        enable = true;
        lfs.enable = true;
        ignores = [
          ".cache/"
          ".DS_Store"
          ".idea/"
          "*.swp"
          "built-in-stubs.jar"
          "dumb.rdb"
          ".elixir_ls/"
          ".vscode/"
          "npm-debug.log"
          "shell.nix"
          ".direnv"
        ];
        settings = {
          user.name = "MoeLeak";
          user.email = "i@leak.moe";
          sendemail.smtpserver = "smtp.gmail.com";
          sendemail.smtpserverport = 587;
          sendemail.smtpencryption = "tls";
          sendemail.smtpuser = "moeleaking@gmail.com";

          alias = {
            st = "status";
            lg = "log --oneline --graph --all --decorate";
          };
          init.defaultBranch = "main";
          push.autoSetupRemote = true;
          pull.rebase = true;
        };
      };
    };
  };
}
