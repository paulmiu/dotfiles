# Ubuntu setup

Run from a complete repository checkout. The platform entry point uses the shared Linux installer.

```bash
bash install/os/ubuntu.sh --help
bash install/os/ubuntu.sh --dry-run --admin-user=paul
sudo bash install/os/ubuntu.sh --admin-user=paul
```

An existing user is added to the distribution's administrator group. A new account can be created interactively, including its sudo password. `--yes` requires an existing account. Only the selected account receives dotfiles; root is the default when invoked directly as root without `--admin-user`.

Package groups: `basic`, `essentials`, `remote`, `terminal`, `search`, `kubernetes`. Kubernetes and Cockpit are opt-in. Mandatory prerequisites (including sudo, Git, CA certificates and OpenSSH) are installed even with `--groups=none`.

```bash
sudo bash install/os/ubuntu.sh --yes --admin-user=paul \
  --groups=basic,essentials,remote,terminal,search \
  --add-ssh-key="$(cat ~/.ssh/id_ed25519.pub)"
```

System upgrades require `--upgrade`. The installer does not perform a distribution upgrade or override package-manager safeguards. Fedora server environment groups are no longer implicitly installed.

Use `--hostname=server-name` to change the hostname and `--reboot` to schedule a reboot after success. Otherwise both are left alone.

`--new-ssh-port=22222` **adds** a port while retaining existing listeners. Configuration is validated with OpenSSH before activation and restored if activation fails. Open the port in any provider firewall, verify a second connection, and remove obsolete listeners separately. The installer does not replace authentication policy or host keys. A backup is kept beside `sshd_config`.

`--skip-ssh` leaves SSH daemon configuration untouched and supports container testing. Hostname, reboot and Cockpit operations still require running systemd.

For socket-activated SSH, new listeners retain the existing interfaces and address families. Socket changes require the service's `KillMode=process` so established sessions survive the combined socket/service restart. Explicit `ListenAddress` settings that prevent a requested port cause setup to stop. Firewall and SELinux rules added for an explicitly requested port remain available for a retry if later activation fails; daemon configuration is rolled back.

Dotfile conflicts are backed up under `~/.local/state/dotfiles/backups/`. Existing Git checkouts and local changes are preserved. A local source checkout supplies a Git bundle of its committed HEAD, so unpublished commits work and uncommitted changes are excluded. `--ref` selects a remote branch, tag or commit for a fresh installation instead. Existing checkouts are never reset or updated automatically.

Use `--skip-plugins` to omit plugin downloads and `--no-shell-change` to retain the current login shell. Plugin installation failures stop the installer; rerunning resumes from the installed repositories. No outbound private SSH key is generated automatically.

The installer stops on failures, but package and account changes are not a system-wide transaction. Inspect the error before rerunning. If a terminated process leaves `/run/dotfiles-installer.lock`, verify no installer is active before removing that empty directory.
