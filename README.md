# Yubikey

Before rebuilding you need to export your age key to a specific folder.

```
$ nix shell nixpkgs#age-plugin-yubikey
$ age-plugin-yubikey --identity --slot 1 > $HOME/.config/sops/age/keys.txt
```

# Pi extensions

`home-manager/pi.nix` enables Home Manager's `programs.pi-coding-agent` module
and deploys local extensions with `home.file`. Their sources live in
`programs/pi/extensions/`; models, credentials, settings and conversation
history remain in the user's writable `~/.pi/agent` directory.

The extensions deployed by `home-manager/pi.nix` are:

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

`home-manager/claude-provider.nix` seeds the providers on the first activation
and enables the proxy at `127.0.0.1:4000`; later edits through the TUI are left
alone. The xin host and key live in `secrets/claude-provider.yaml` and are
decrypted to a user-owned environment file, so no credential reaches the Nix
store. Edit it with:

```bash
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops secrets/claude-provider.yaml
```
