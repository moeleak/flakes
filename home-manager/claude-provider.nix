{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}:

# Provider switching for Claude Code via cc-switch-cli.
#
# cc-switch keeps provider profiles and runs a local proxy that adapts
# OpenAI-compatible upstreams (the ones Pi uses) to the Anthropic API, then
# points ~/.claude/settings.json at that proxy. Seeds the providers from
# secrets/claude-provider.yaml on first activation; afterwards use
# `cc-switch` (TUI), `cc-switch use <id>`, or `claude-direct` (subscription).
let
  host = lib.attrByPath [ "networking" "hostName" ] "" osConfig;
  # Same key-source selection as system/sops.nix.
  useSshKey = builtins.elem host [
    "LoliIsland-PC-Nix"
    "biuh-lab"
    "lp4a"
  ];
  home = config.home.homeDirectory;

  ccs = lib.getExe pkgs.cc-switch-cli;
  envFile = config.sops.templates."claude-provider-env".path;

  port = 4000;

  # id, display name, base URL env var or literal, API key env var or literal,
  # model. Mirrors the providers configured for Pi.
  providers = [
    {
      id = "xin-deepseek";
      name = "xin / deepseek-v4.1-flash";
      baseUrl = "\${XIN_BASE_URL}";
      apiKey = "\${XIN_API_KEY}";
      model = "deepseek-v4.1-flash";
    }
    {
      id = "xin-qwen";
      name = "xin / qwen3.8-27b";
      baseUrl = "\${XIN_BASE_URL}";
      apiKey = "\${XIN_API_KEY}";
      model = "qwen3.8-27b";
    }
    {
      id = "lab";
      name = "lab llama.cpp / qwen3.8";
      baseUrl = "http://100.64.44.88:8080/v1";
      apiKey = "sk-local";
      model = "qwen3.8-flash-next-unsloth-ud-q4_k_xl";
    }
    {
      id = "local";
      name = "local llama.cpp / qwen3.8";
      baseUrl = "http://127.0.0.1:8080/v1";
      apiKey = "sk-local";
      model = "qwen3.8-flash-next-iq2_xs";
    }
  ];

  addProvider = p: ''
    if ! ${ccs} provider list | grep -qF '${p.id}'; then
      ${ccs} --app claude provider add \
        --id '${p.id}' --name '${p.name}' \
        --base-url "${p.baseUrl}" --api-key "${p.apiKey}" \
        --api-format openai_chat --model '${p.model}'
    fi
  '';
in
{
  home.packages = [
    pkgs.cc-switch-cli

    # Launch Claude with another provider for one run, without switching the
    # global selection. `claude-direct` is the Anthropic subscription.
    (pkgs.writeShellScriptBin "claude-with" ''
      exec ${ccs} start claude "$@"
    '')
    (pkgs.writeShellScriptBin "claude-direct" ''
      exec ${ccs} start claude claude-official -- "$@"
    '')
  ];

  # cc-switch owns the ANTHROPIC_* variables in ~/.claude/settings.json, so they
  # must not also be exported here (environment variables win over its config).
  home.sessionVariables = {
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
  };

  sops = {
    defaultSopsFile = ../secrets/claude-provider.yaml;
    age.plugins = [ pkgs.age-plugin-yubikey ];
    age.keyFile = lib.mkIf (!useSshKey) "${home}/.config/sops/age/keys.txt";
    age.sshKeyPaths = lib.optional useSshKey "${home}/.ssh/id_ed25519";

    secrets = {
      "claude-provider-xin-base-url" = {
        sopsFile = ../secrets/claude-provider.yaml;
        key = "xin-base-url";
      };
      "claude-provider-xin-api-key" = {
        sopsFile = ../secrets/claude-provider.yaml;
        key = "xin-api-key";
      };
    };

    templates."claude-provider-env" = {
      content = ''
        XIN_BASE_URL=${config.sops.placeholder."claude-provider-xin-base-url"}
        XIN_API_KEY=${config.sops.placeholder."claude-provider-xin-api-key"}
      '';
      mode = "0400";
    };
  };

  home.activation.claude-providers = lib.hm.dag.entryAfter [ "sops-nix" ] ''
    if ${lib.escapeShellArg ccs} provider list > /dev/null 2>&1; then
      set -eu
      . ${lib.escapeShellArg envFile}
      ${lib.concatMapStringsSep "\n      " addProvider providers}

      # The port cannot be changed while the route is enabled.
      if ! ${ccs} --app claude proxy config --listen-port ${toString port}; then
        ${ccs} proxy disable --app claude || true
        ${ccs} --app claude proxy config --listen-port ${toString port}
      fi
      ${ccs} proxy enable --app claude

      # Pick a default only when nothing meaningful is selected yet; later
      # activations leave the user's current choice alone.
      if ! ${ccs} provider current 2>/dev/null | grep -qE '^[[:space:]]*ID:'; then
        ${ccs} use xin-deepseek
      elif ${ccs} provider current 2>/dev/null | grep -qE 'ID:[[:space:]]*default$'; then
        ${ccs} use xin-deepseek
      fi
    else
      echo "cc-switch: could not read provider state, skipping seeding" >&2
    fi
  '';
}
