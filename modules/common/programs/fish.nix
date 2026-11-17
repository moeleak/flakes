# fish as the system shell, plus the user's prompt and shell helpers.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.fish;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  # colmena's generated completion knows neither this flake's nodes nor the
  # goals, and offers files for both; add them, the nodes and tags taken from
  # the hive.
  colmenaCompletion =
    let
      hive = lib.removeAttrs inputs.self.colmena [
        "meta"
        "defaults"
        "network"
      ];
      tags = lib.unique (lib.concatMap (node: node.deployment.tags or [ ]) (lib.attrValues hive));
      selectors = lib.concatStringsSep " " (map (tag: "@${tag}") tags ++ lib.attrNames hive);
      goals = {
        switch = "Activate now and at boot";
        boot = "Activate at the next boot";
        test = "Activate now, not at boot";
        dry-activate = "Show what activation would do";
        build = "Build only";
        push = "Build and copy only";
        upload-keys = "Upload keys only";
      };
      when = subcommands: lib.concatMapStringsSep "; or " (sub: "__fish_colmena_using_subcommand ${sub}") subcommands;
      goalLines = lib.mapAttrsToList (
        goal: description:
        "complete -c colmena -n \"${
          when [
            "apply"
            "apply-local"
          ]
        }\" -f -a ${goal} -d '${description}'"
      ) goals;
    in
    ''
      source ${pkgs.colmena}/share/fish/vendor_completions.d/colmena.fish

      complete -c colmena -e -l on
      complete -c colmena -n "${
        when [
          "apply"
          "build"
          "exec"
          "upload-keys"
        ]
      }" -l on -d 'Node selector' -x -a "(__fish_append , ${selectors})"
      ${lib.concatStringsSep "\n" goalLines}
    '';
in
{
  options.my.programs.fish = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = { };
  };

  config = lib.mkIf (cfg != null) {
    programs.fish.enable = true;

    home-manager.users.${config.my.user} = lib.mkIf (config.my.home != null) {
      programs.fish = {
        enable = true;

        completions.cargo = builtins.readFile "${pkgs.fish.src}/share/completions/cargo.fish";
        completions.colmena = colmenaCompletion;

        shellInit = lib.mkIf isDarwin ''
          source /Users/lolimaster/miniconda3/etc/fish/conf.d/conda.fish
          for p in /run/current-system/sw/bin /etc/profiles/per-user/$USER/bin
            if not contains $p $fish_user_paths
              set -g fish_user_paths $p $fish_user_paths
            end
          end
        '';

        interactiveShellInit = ''
          set -g fish_greeting ""

          set -g fish_color_autosuggestion brblack
          set -g fish_color_cancel --reverse
          set -g fish_color_command 87afd7
          set -g fish_color_comment red
          set -g fish_color_cwd green
          set -g fish_color_cwd_root red
          set -g fish_color_end green
          set -g fish_color_error brred
          set -g fish_color_escape brcyan
          set -g fish_color_history_current --bold
          set -g fish_color_host normal
          set -g fish_color_host_remote yellow
          set -g fish_color_keyword normal
          set -g fish_color_match --background=brblue
          set -g fish_color_normal normal
          set -g fish_color_operator brcyan
          set -g fish_color_option cyan
          set -g fish_color_param cyan
          set -g fish_color_quote yellow
          set -g fish_color_redirection cyan --bold
          set -g fish_color_search_match bryellow --background=brblack
          set -g fish_color_selection white --bold --background=brblack
          set -g fish_color_status red
          set -g fish_color_user brgreen
          set -g fish_color_valid_path --underline

          set -g fish_pager_color_background normal
          set -g fish_pager_color_completion normal
          set -g fish_pager_color_description yellow --italics
          set -g fish_pager_color_prefix normal --bold --underline
          set -g fish_pager_color_progress brwhite --background=cyan
          set -g fish_pager_color_secondary_background normal
          set -g fish_pager_color_secondary_completion normal
          set -g fish_pager_color_secondary_description normal
          set -g fish_pager_color_secondary_prefix normal
          set -g fish_pager_color_selected_background --reverse
          set -g fish_pager_color_selected_completion normal
          set -g fish_pager_color_selected_description normal
          set -g fish_pager_color_selected_prefix normal

          set -g fish_key_bindings fish_default_key_bindings
        '';
      };

      programs.fzf = {
        enable = true;
        enableFishIntegration = true;
      };

      programs.zoxide.enable = true;
      programs.starship.enable = true;
    };
  };
}
