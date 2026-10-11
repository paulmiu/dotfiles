# macOS setup

Run the installer as the account receiving the dotfiles, **without sudo**. Homebrew and plugins run as that account. The installer requests sudo only when Homebrew bootstrap or login-shell registration needs it.

```bash
bash install/os/macos.sh --help
bash install/os/macos.sh --dry-run
bash install/os/macos.sh
```

Package groups: `core`, `essentials`, `terminal`, `developer`, `media`, `kubernetes`, `gui`, `fonts`, `preferences`.

Core tools, shell essentials, terminal tools, developer tools and Fira Code are selected by default. Media/network tools, Kubernetes, iTerm2, and preference changes require explicit selection. Git and coreutils are prerequisites even with `--groups=none`.

```bash
bash install/os/macos.sh --yes --groups=essentials,terminal,fonts
```

An unattended first Homebrew installation needs an existing sudo credential or suitable sudo policy. On a new Mac, run interactively. The official Homebrew installer remains responsible for its OS and Xcode command-line-tools requirements.

- Homebrew's default prefix is detected for Apple Silicon or Intel.
- GNU command names are linked into `~/.local/share/dotfiles/gnubin`, never over Homebrew-managed binaries. That path is registered with Fish when both `core` and `essentials` are selected.
- Gatekeeper remains enabled. The installer does not alter system security assessment policy.
- `preferences` imports the bundled app preferences and changes typing defaults in the current account. Previous preferences are exported to a unique backup under `~/Library/Preferences/` first.
- Existing dotfiles are backed up before linking. Existing checkouts and local changes are preserved.
- `--skip-plugins` skips Fish/Vim/tmux plugin installation. `--no-shell-change` keeps the existing login shell.
- `--admin-user` may name only the current account. Server-specific SSH-port, hostname, upgrade and reboot options are rejected.

Dependencies are fetched over HTTPS. The Homebrew bootstrap and initial plugin-manager checkouts use pinned upstream commits; package versions and plugins selected by your configuration follow their upstream sources. Review/update those pins deliberately when maintaining the installer.

## Preference archives

The standalone `defaults-export` and `defaults-import` helpers require Python 3. Export creates a new ZIP in your home directory (or at a supplied path) and refuses to overwrite an existing backup. Import validates every archive member and plist before writing, backs up affected domains, and attempts to restore them if an import fails. It never extracts archive paths or deletes a fixed working directory.

```bash
bash install/os/resources/macos/scripts/defaults-export ~/my-preferences.zip
bash install/os/resources/macos/scripts/defaults-import ~/my-preferences.zip
```

Only the current account's preferences are handled by default. `--include-root` additionally handles root's preferences through sudo. The `global/` directory in legacy archives refers to root's domains, not machine-wide settings.
