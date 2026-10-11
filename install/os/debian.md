# Debian VPS setup

This entry point targets **Debian 13 (Trixie)** or newer. It uses the shared Linux implementation and the same APT package selection as Ubuntu; there is no duplicated provisioning script to maintain.

```bash
bash install/os/debian.sh --help
bash install/os/debian.sh --dry-run --admin-user=paul
sudo bash install/os/debian.sh --admin-user=paul
```

The main launcher detects `ID=debian` for both local and remote installations:

```bash
bash install/install.sh --remote=root@debian-vps.example --admin-user=paul
```

Supply an existing account with `--yes`, or run interactively to create an administrator and set their sudo password. Minimal images do not need sudo, Git or CA certificates preinstalled when starting a complete checkout as root; those prerequisites are installed before account and dotfile setup. The standalone HTTPS bootstrap still needs curl or wget, trusted CA certificates, Bash and tar before it can download the checkout.

The default package groups are `basic`, `essentials`, `remote`, `terminal` and `search`. `kubernetes` is opt-in and installs the distribution's `kubectx` package, including `kubens`.

```bash
sudo bash install/os/debian.sh --yes --admin-user=paul \
  --groups=basic,essentials,remote,terminal,search \
  --add-ssh-key="$(cat ~/.ssh/id_ed25519.pub)"
```

As with Ubuntu, Debian packages provide `batcat` and `fdfind` for `bat` and `fd-find`; the existing shell configuration handles those names.

`--upgrade`, `--hostname` and `--reboot` are explicit choices. `--new-ssh-port` adds a listener while retaining existing ports. A running systemd is required for SSH changes; use `--skip-ssh` for container provisioning. Existing SSH authentication policy and host keys remain intact.

See [the shared Linux behavior documented for Ubuntu](ubuntu.md) for backups, existing checkouts, plugin installation, error handling and SSH recovery. Container tests cover Debian 13 package installation, account setup, dotfile links, repeat runs and the OpenSSH parser; full provider-firewall and systemd activation behavior still needs a disposable VPS/VM test.
