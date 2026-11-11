# Layout

Every module is always loaded and is switched by an option under `my.*`, so a
host file only states what the machine is.

- `modules/common/` works on NixOS and macOS, `modules/nixos/` on NixOS only.
  Every `.nix` file in them is picked up automatically. Each module declares
  one option, e.g. `my.services.samba`, that is either `null` (off) or an
  attribute set (on, possibly with settings).
- `my.variant` (`minimal`, `desktop` or `server`) decides which modules are on
  by default. A host overrides any of them with `= { };` or `= null;`.
- `hosts/<system>/<name>/` is picked up automatically too; the directory name
  becomes the hostname. It holds the hardware and anything unique to the
  machine.
- There is no separate Home Manager tree. A module puts its user-level
  settings under `home-manager.users.${config.my.user}` next to its system
  ones; `my.home` switches the user environment as a whole.
  `modules/common/packages/` holds the package lists (`cli`, `dev`,
  `desktop`), `modules/common/programs/` one file per configured program.
- `pkgs/` holds packages built here: `pkgs/neovim/` (nixvim, one file per
  concern) and `pkgs/gal.nix` (the galgame launcher).

A new desktop is a directory with `hardware-configuration.nix` and:

```nix
{
  imports = [ ./hardware-configuration.nix ];
  my = {
    variant = "desktop";
    desktop.sway = { };
  };
  system.stateVersion = "25.05";
}
```

# Adding a feature

Nothing has to be registered in `flake.nix`; put the file in the right place.

For a system feature, create a file in `modules/nixos/` (NixOS only) or
`modules/common/` (NixOS and macOS):

```nix
# modules/nixos/services/foo.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.my.services.foo;
in
{
  options.my.services.foo = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    services.foo.enable = true;
  };
}
```

and switch it on in the hosts that want it with `my.services.foo = { };`.

- To have it on by default for a kind of machine, set `default` to
  `if config.my.variant == "desktop" then { } else null` (or
  `!= "minimal"` for desktops and servers).
- To give it settings, add `options.port = lib.mkOption { ... };` inside
  `submodule { }`, read it as `cfg.port`, and set
  `my.services.foo.port = 8080;` in the host.
  `modules/nixos/hardware/nvidia.nix` is an example.
- If it needs a secret, add the value to a file in `secrets/` and declare it
  as described under [Secrets](#secrets).

Everything else:

| What | Where |
| --- | --- |
| Configuration only one machine will ever use | its `hosts/<system>/<name>/` directory, like `biuh-lab/frp.nix` |
| A package for the user | the matching list in `modules/common/packages/` |
| User-level settings of a program (dotfiles, Home Manager options) | the program's own module, under `home-manager.users.${config.my.user}`; `modules/common/programs/git.nix` is an example |
| A program packaged here | `pkgs/`, used through `pkgs.callPackage`, like `pkgs/gal.nix` |
| A new machine | a new `hosts/<system>/<name>/default.nix`, as shown above |

Two things to watch for:

- `git add` new files first. A flake does not see untracked files, and the
  error is a missing file or an option that does not exist.
- `modules/common/` may only set options that exist on both systems. A
  NixOS-only option such as `boot.*` or `systemd.*` breaks the Mac even while
  the feature is off.

Check with `nixos-rebuild build --flake .#<host>` before switching.

# Secrets

Secrets live in `secrets/*.yaml`, encrypted to the two recipients in
`.sops.yaml`. A module declares the ones it needs by name and the file that
contains the key is found automatically:

```nix
sops.secrets."frp-token" = { };
```

Edit or create a file with:

```bash
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops secrets/<file>.yaml
```

Hosts decrypt with the main user's `~/.ssh/id_ed25519`. Hosts that set
`my.sops.yubikey = true` (the Mac and the laptop) instead need the YubiKey
plugged in during a rebuild, with its identity exported once:

```
$ nix shell nixpkgs#age-plugin-yubikey
$ age-plugin-yubikey --identity --slot 1 > $HOME/.config/sops/age/keys.txt
```

# Pi extensions

`modules/common/programs/pi` enables Home Manager's `programs.pi-coding-agent` module
and deploys local extensions with `home.file`. Their sources live in
`modules/common/programs/pi/extensions/`; models, credentials, settings and conversation
history remain in the user's writable `~/.pi/agent` directory.

The extensions deployed from that directory are:

- `/rescue` preserves the complete conversation in a new session file, replaces
  the active context with local excerpts, and switches to the recovery copy. It
  does not call a model to prepare the excerpts. Press Enter to submit the
  continuation request it places in the editor. Excerpts can omit details; the
  complete history is retained for reference. This restores context without
  fixing an inference backend fault.
- `token-speed` shows a live tokens-per-second status line. `/speed [toggle|on|off|status]`
  controls it and saves the choice to `settings.json`.
- `unix-keys` binds Ctrl-P/Ctrl-N to readline-style history and list navigation.

After rebuilding the host or Home Manager configuration, new Pi processes load
the extensions automatically. In an already running Pi, use `/reload` once.
Run `/rescue` or `/rescue <additional instructions>`; `/rescue help` shows usage.

To run all 14 tests, including a real Pi process, against the packages pinned
by this flake (use `aarch64-darwin` on the Mac):

```bash
nix build .#checks.x86_64-linux.pi-rescue
```

# Proxy

The `proxy` selector uses Hysteria 2 on UDP 8443: `hysteria-lax` is the
default and `hysteria-as3` is the alternate. VLESS outbounds are retired.
The existing Lab relay and `auto` routing remain available.
UDP 8443 avoids the UDP 443 filtering observed on the current client network.

Node addresses, separate passwords, and TLS public-key pins are encrypted in
`secrets/sing-box.yaml`. Each VPS stores its Hysteria configuration in
`/etc/nixos/hysteria.nix`, its password in
`/etc/nixos/secrets/hysteria-password`, and its ECDSA certificate/key under
`/var/lib/sing-box/hysteria/`. Clients authenticate the pinned key; replacing a
server key requires updating that node's encrypted `sing-box-hysteria-*-pin`.
The servers retain their existing VLESS listeners for other clients.

# Claude Code providers

Claude Code speaks the Anthropic API while the Pi providers are
OpenAI-compatible, so providers are managed through
[cc-switch-cli](https://github.com/SaladDay/cc-switch-cli): it stores the
provider profiles, runs a loopback proxy that adapts OpenAI chat completions to
the Anthropic API, and writes the resulting `ANTHROPIC_*` settings into
`~/.claude/settings.json`.

Switch providers with the TUI (`cc-switch`) or `cc-switch use <id>`. The seeded
ids mirror the Pi providers:

| id | upstream |
| --- | --- |
| `claude-official` | Anthropic subscription (built in) |
| `xin-deepseek` | xin / `deepseek-v4.1-flash` (default) |
| `xin-qwen` | xin / `qwen3.8-27b` |
| `lab` | lab llama.cpp |
| `local` | local llama.cpp |

`claude-with <id> [args]` uses a provider for one run without switching,
`claude-direct [args]` runs the Anthropic subscription. Do not export
`ANTHROPIC_*` globally — environment variables take precedence over
cc-switch's configuration.

`modules/common/programs/claude` seeds the providers on the first activation
and enables the proxy at `127.0.0.1:4000`; later edits through the TUI are left
alone. The xin host and key live in `secrets/claude-provider.yaml` and are
decrypted to a user-owned environment file, so no credential reaches the Nix
store. Edit it with:

```bash
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops secrets/claude-provider.yaml
```
