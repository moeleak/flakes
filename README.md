# Yubikey

Before rebuilding you need to export your age key to a specific folder.

```
$ nix shell nixpkgs#age-plugin-yubikey
$ age-plugin-yubikey --identity --slot 1 > $HOME/.config/sops/age/keys.txt
```

