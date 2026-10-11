# Dotfiles

Personal shell, editor and terminal configuration, stored in a Homeshick-compatible checkout under `~/.homesick/repos/dotfiles`.

## Install from a checkout

```bash
git clone https://github.com/mamiu/dotfiles.git
cd dotfiles
bash install/install.sh --help
bash install/install.sh --local --dry-run
bash install/install.sh --local
```

The launcher detects Debian, Ubuntu, Fedora or macOS. Linux system changes require root; the launcher uses sudo when needed. macOS installation runs as the current account without sudo around the whole script.

Select an existing account or create a Linux admin interactively:

```bash
bash install/install.sh --local --admin-user=paul
```

Dotfiles go only to that account. Existing checkouts and local changes are preserved. Conflicting configuration files are backed up before linking. A local checkout supplies its committed HEAD; staged and unstaged changes are excluded from new installations. `--ref` can select a remote branch, tag or commit for a fresh dotfiles checkout.

## Remote setup

```bash
bash install/install.sh --remote=root@server.example --admin-user=paul
bash install/install.sh --remote=my-existing-ssh-alias
bash install/install.sh --remote=root@server.example --port=22222 --dry-run
```

Remote setup uses normal OpenSSH host verification and existing SSH configuration. Verify a new host's fingerprint with your provider before accepting it. Changed keys are never silently removed or accepted. `--yes` uses batch-mode SSH and requires an already trusted host and working key authentication.

The launcher uploads a committed snapshot over SCP and executes that same version, including unpublished installer commits. Commit changes before testing them remotely. It does not modify your local SSH config or generate private keys. Use explicit `--add-ssh-key="$(cat ~/.ssh/id_ed25519.pub)"` to authorize an existing public key.

`--port` selects the current connection port. `--new-ssh-port` adds a server listener while retaining existing ports; verify the new connection before removing old listeners separately. Provider firewall rules still need to permit the port.

## Standalone bootstrap

After the modular installer has been published on the requested ref, it can bootstrap a complete, consistent snapshot:

```bash
curl --fail --proto '=https' --tlsv1.2 -o install-dotfiles.sh \
  https://raw.githubusercontent.com/mamiu/dotfiles/main/install/install.sh
# Review the downloaded script before executing it.
bash install-dotfiles.sh --local
```

Use a reviewed commit hash in the download URL and `--ref` to pin the bootstrap source. The bootstrap resolves the selected ref once, downloads its full archive over HTTPS into a private temporary directory, and cleans up afterward. Directly downloading individual OS scripts is no longer supported; they need the shared library from the same checkout.

## Options and behavior

Run `--help` for all options and an OS entry point's `--help` for package groups. Useful options include `--yes`, `--groups=essentials,terminal,search`, `--groups=none`, `--skip-plugins`, `--no-shell-change`, and `--dry-run`.

- Mandatory prerequisites are installed even with no optional package groups.
- System upgrades, hostname changes and reboots are explicit Linux options.
- macOS preference imports are opt-in; Gatekeeper is not disabled.
- Required command failures return nonzero. Per-user launcher logs are private under `~/.local/state/dotfiles/logs/`.
- SSH configuration is validated before activation and restored on activation failure. Other package/account changes are not automatically rolled back.
- Initial plugin-manager and Homebrew bootstrap revisions are pinned in the source. Package versions and configured plugins follow upstream; this is not a fully reproducible OS image builder.

See [Debian](install/os/debian.md), [Ubuntu](install/os/ubuntu.md), [Fedora](install/os/fedora.md), and [macOS](install/os/macos.md) for details.

## Development

```bash
bash install/tests/check.sh
```

Requires Bash, ShellCheck, shfmt and Python 3. Regression tests use temporary directories and mocked system commands. Linux integration checks must run in disposable containers/VMs; never run a provisioning integration test on your workstation. The macOS installer supports the system Bash 3.2.

CI also runs isolated smoke tests on Debian 13, Ubuntu 24.04 and Fedora 44, plus the unit suite on macOS's Bash 3.2. To reproduce a Linux test:

```bash
docker run --rm -v "$PWD:/workspace:ro" -w /workspace debian:13-slim \
  bash install/tests/container-smoke.sh debian
```

These tests exercise package/account setup and reruns. OpenSSH parsing and rollback are tested with the real `sshd` binary and mocked service activation; containers do not establish that a provider's firewall or systemd listener works on a real VPS.
