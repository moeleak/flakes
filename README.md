# Yubikey

Before rebuilding you need to export your age key to a specific folder.

```
$ nix shell nixpkgs#age-plugin-yubikey
$ age-plugin-yubikey --identity --slot 1 > $HOME/.config/sops/age/keys.txt
```

# Hydra and R2 cache

`biuh-lab` runs an official Hydra instance for the three x86_64 NixOS
configurations exported under `hydraJobs.nixos`. Hydra polls
`github:moeleak/flakes/main` every five minutes and writes signed build outputs
to the `nix-cache` Cloudflare R2 bucket. The evaluator permits
import-from-derivation because the existing Home Manager configuration
generates Fish completions during evaluation; the jobset source remains the
fixed public repository above.

The public endpoints are:

- Hydra: `https://hydra.leak.moe`
- Nix binary cache: `https://cache.leak.moe`

## Cloudflare preparation

Before deploying the NixOS configuration:

1. Create an R2 bucket named `nix-cache` and attach the public custom domain
   `cache.leak.moe`. Do not configure an object lifecycle rule.
2. Create an R2 S3 API token with Object Read & Write access restricted to that
   bucket. Save its Access Key ID and Secret Access Key.
3. Create a dedicated locally-managed Cloudflare Tunnel for Hydra, route
   `hydra.leak.moe` to it, and download its credentials JSON. The local ingress
   configuration is managed by NixOS and only forwards to
   `http://127.0.0.1:3000`.

Populate the encrypted deployment values without putting credentials on a
command line:

```console
$ read -r R2_ACCOUNT_ID
$ read -r R2_ACCESS_KEY_ID
$ read -rs R2_SECRET_ACCESS_KEY; echo
$ export R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY
$ export CLOUDFLARE_TUNNEL_CREDENTIALS_FILE=/path/to/tunnel-credentials.json
$ ./scripts/set-hydra-deployment-secrets
$ unset R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY
```

The cache signing key and a random Hydra administrator password are already
stored in `secrets/hydra.yaml`. To choose a different initial password, also
set `HYDRA_ADMIN_PASSWORD` when running the script. Otherwise, retrieve the
generated password with the SSH key used by this repository:

```console
$ SOPS_AGE_KEY_CMD="nix shell nixpkgs#ssh-to-age -c ssh-to-age -private-key -i $HOME/.ssh/id_ed25519" \
    nix run nixpkgs#sops -- --decrypt --extract '["hydra-admin-password"]' \
    secrets/hydra.yaml
```

## Deployment and verification

Evaluate and deploy from the working tree with:

```console
$ nix --option allow-import-from-derivation true flake check path:. --no-build
$ sudo nixos-rebuild test --flake path:.#biuh-lab
$ systemctl status hydra-server hydra-evaluator hydra-queue-runner \
    hydra-bootstrap hydra-cloudflared
```

Commit and push these changes to `github:moeleak/flakes/main` before expecting
the remote jobset to discover `hydraJobs`.

After verifying the UI, jobset, and a test upload, make the generation
persistent with `nixos-rebuild switch`. Clients importing `system/nix.nix`
already trust `https://cache.leak.moe` and its `cache.leak.moe-1` signing key.

If any R2 or Tunnel value is still a `CHANGE_ME` placeholder,
`hydra-secrets-check.service` deliberately prevents Hydra and the Tunnel from
starting.
