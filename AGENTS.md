# Notes for agents

## Deploying Lab (biuh-lab)

Lab has no `tailscaled`: its Tailscale address (100.64.44.88, `biuh-lab`) is
sing-box's own Tailscale endpoint (modules/common/services/sing-box). A switch
that restarts sing-box, which most do (and NetworkManager and Docker with it),
takes Lab off Tailscale and cuts the SSH session that runs the activation. A
plain `colmena apply --on @lab` then stops in the middle: the old units are
stopped and the new ones never start, and Lab stays off Tailscale until someone
logs in from the campus network.

So the activation must not run in the SSH session. Build first, then switch
under `systemd-run`, as `nixos-rebuild` does, which outlives the SSH session:

```bash
colmena apply --on @lab build          # builds on Lab itself (buildOnTarget),
                                       # and prints the system it built
# then on Lab, as root, with the system it built:
nix-env -p /nix/var/nix/profiles/system --set /nix/store/…-nixos-system-biuh-lab-…
systemd-run --unit=lab-switch --collect --no-block --property=Type=oneshot \
  /nix/var/nix/profiles/system/bin/switch-to-configuration switch
systemctl status lab-switch            # once Lab is back on Tailscale
```

Or, from a session on the campus network (`ssh moeleak@10.90.0.3`, which
doesn't go through sing-box), `colmena apply-local --sudo` on Lab.

The switch takes Lab off Tailscale for a minute or more; Docker, whose
containers start slowly from the HDD, is the last to come up.

## VMs on Lab

The VMs are declared one file each in `modules/nixos/services/vms/<host>/`
(see `lib/vms.nix`). `vm-<name>.service` runs each; a deploy never restarts
it, so changes to a VM (its seed, cores, memory) apply on
`systemctl restart vm-<name>`, which shuts it down over ACPI first. Its disk,
`/var/lib/vms/<name>/disk.qcow2`, is made once and never recreated. On Lab,
`vm-console <name>` is its serial console (Ctrl-] leaves), and
`ssh root@192.168.233.<id>` reaches it.
