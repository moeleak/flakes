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

Secrets live in `secrets/*.yaml`, encrypted to the user's two recipients in
`.sops.yaml`; `sing-box.yaml` is also encrypted to the VPS that read it. A
module declares the ones it needs by name and the file that contains the key is
found automatically:

```nix
sops.secrets."frp-token" = { };
```

Edit or create a file with:

```bash
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops secrets/<file>.yaml
```

Hosts decrypt with the main user's `~/.ssh/id_ed25519`; the VPS
(`my.sops.hostKey = true`) with their `/etc/ssh/ssh_host_ed25519_key`, whose age
recipient is `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`. After changing
the recipients of a file, run `sops updatekeys secrets/<file>.yaml`. A nested
key such as `sing-box-users/ada/token` is found by its top-level part. Hosts that set
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

The `proxy` selector uses VLESS with XTLS Vision over TLS on TCP 8443: `lax`
is the default and `as3` the alternate. The client's TLS looks like Chrome's
(uTLS), and the nodes have ordinary Let's Encrypt certificates for
`<node>.leak.moe`. The clients connect by name, so a node's address changes
with its DNS record alone. The existing Lab relay and `auto` routing remain
available.

The cache file persists FakeIP mappings (`store_fakeip = true`) so DNS
addresses cached by applications remain valid after a sing-box restart.

## Nodes

`lib/proxy.nix` lists the nodes, the VLESS port and the users; the clients and
`modules/nixos/services/proxy-node` both read it. Each node
(`hosts/x86_64-linux/LoliIsland-VPS-{AS3,lax}`, `my.services.proxy-node`) runs
sing-box with the VLESS inbound. sing-box obtains and renews its certificate
itself (a `certificate_providers` entry); Caddy holds ports 80 and 443 and
forwards `http://<node>.leak.moe/.well-known/acme-challenge/` to it.

sing-box's VLESS inbound has no fallback: a connection that is not VLESS is
closed after the TLS handshake instead of reaching a web server.

The node named by `profiles.node` (LAX) also runs `proxy-config`
(`pkgs/proxy-config`) behind Caddy, which serves each user's sing-box profile
at `https://config.leak.moe/query?token=<token>`. A user has one token, and the
profile contains every node that lists the user (TUN, mainland China direct,
`auto` picks the fastest node; needs sing-box 1.12 or later). Adding
`&tailscale=true` returns the same profile with a Tailscale endpoint (sing-box
1.13 or later): tailnet addresses, subnet routes and `*.ts.net` names go
through Tailscale, whose own connections use the proxy. It carries no auth
key; on the first start sing-box logs a login URL, and the user signs in to
whichever tailnet they like. `&lab=true` makes the Lab relay (`lab` in
`lib/proxy.nix`) the default for `proxy`; it only answers on Lab's campus
network, so the nodes stay selectable. The two combine, and each user has a
profile for every combination. Opened in a browser, the URL shows a page with
a QR code (and a link) that the sing-box apps import as a remote profile, and
a switch for each option; the apps themselves, curl and `&qr-code=false` get
the JSON. The page uses Material Web, bundled with esbuild from
`pkgs/proxy-config/web` (pinned in its `package-lock.json`) and served from
`/assets/`. Profiles are rendered and
checked with `sing-box check` when the service starts.
`config.leak.moe` must resolve to that node (a DNS-only CNAME to
`lax.leak.moe` in Cloudflare); to move it, change `profiles.node`, deploy both
nodes and repoint the record.

Secrets, in `secrets/sing-box.yaml` unless noted:

| Key | What |
| --- | --- |
| `sing-box-vless-uuid` | the flake clients' UUID (user `flakes` on every node) |
| `sing-box-users.<user>.{uuid,token}` | the user's UUID on every node, and the profile token |
| `sing-box-lab-password` (`sing-box-lab.yaml`) | the Lab relay's password; also encrypted to the node in `profiles.node`, which renders it into the profiles |

To add a user, add the name to the nodes in `lib/proxy.nix` and its `uuid`
(`uuidgen`) and `token` (`openssl rand -hex 16`) under `sing-box-users` with
`sops secrets/sing-box.yaml`, then deploy both nodes. To print a user's
profile URL:

```bash
nix shell nixpkgs#sops nixpkgs#age-plugin-yubikey -c sops decrypt \
  --extract '["sing-box-users"]["ada"]["token"]' secrets/sing-box.yaml |
  sed 's|^|https://config.leak.moe/query?token=|'
```

## Deploying a VPS

The VPS are too small to evaluate or build their systems, so Lab builds them.
`my.programs.ssh` provides the `as3` and `lax` SSH aliases (root, port 2333)
and their host keys on every machine here:

```bash
nixos-rebuild switch --flake .#LoliIsland-VPS-AS3 --target-host as3 --build-host Lab --use-substitutes
nixos-rebuild switch --flake .#LoliIsland-VPS-lax --target-host lax --build-host Lab --use-substitutes
```

`--build-host` copies every derivation to Lab one round trip at a time, which
takes tens of minutes from a machine far from Lab. From there (or from the
Mac, which has no `nixos-rebuild`), run the same command on Lab without
`--build-host`, after pushing:

```bash
ssh Lab
cd ~/Projects/flakes && git pull
nixos-rebuild switch --flake .#LoliIsland-VPS-AS3 --target-host as3 --use-substitutes
```

`/etc/nixos` on the VPS is empty; the old channel configuration is archived in
`/root/nixos-legacy-20261117.tar.gz`.

The provider (Proxmox) hands out each VPS's addresses on a cloud-init drive,
and cloud-init writes them for systemd-networkd at every boot
(`my.system.vps`). To change a node's IP, use the provider's panel, which
needs the QEMU guest agent (running) and reboots the VPS with the new
address, then update `<node>.leak.moe` in Cloudflare.

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
