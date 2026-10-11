#!/usr/bin/env bash
# macOS provisioning runs as the target account. Elevate only shell registration.
# shellcheck source=install/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

macos_groups() {
    GROUP_IDS=(core essentials terminal developer media kubernetes gui fonts preferences)
    GROUP_LABELS=('GNU command-line tools' 'Fish, tmux, Vim and search tools' 'terminal UI tools' 'shell developer tools' 'media/network tools' 'Kubernetes tools' 'iTerm2' 'Fira Code font' 'bundled app preferences and developer typing defaults')
    GROUP_DEFAULTS=(yes yes yes yes no no no yes no)
}

macos_packages() {
    FORMULAE=(git coreutils)
    CASKS=()
    if group_selected core; then
        FORMULAE+=(binutils diffutils findutils gnu-getopt gawk gnutls grep gnu-sed gnu-tar gzip gnu-indent gnu-which gnu-time less python bash openssh sevenzip rsync wget netcat wdiff unzip watch)
    fi
    if group_selected essentials; then FORMULAE+=(mosh fish tmux vim fzf bat fd ripgrep jq gnupg nmap); fi
    if group_selected terminal; then FORMULAE+=(ncdu htop nnn tig); fi
    if group_selected developer; then FORMULAE+=(reattach-to-user-namespace shellcheck shfmt); fi
    if group_selected media; then FORMULAE+=(libpq ffmpeg tree pipenv deno rclone sshuttle yt-dlp); fi
    if group_selected kubernetes; then FORMULAE+=(kubernetes-cli helm kubectx k9s k3d velero); fi
    if group_selected gui; then CASKS+=(iterm2); fi
    if group_selected fonts; then CASKS+=(font-fira-code); fi
}

macos_brew() {
    if [[ $(uname -m) == arm64 ]]; then BREW_PREFIX=/opt/homebrew; else BREW_PREFIX=/usr/local; fi
    BREW="$BREW_PREFIX/bin/brew"
    if [[ ! -x $BREW ]]; then
        log 'Installing Homebrew using its official installer.'
        if [[ $ASSUME_YES == true ]]; then
            sudo -n -v || die 'Homebrew bootstrap needs sudo credentials; run interactively first.'
        else
            sudo -v
        fi
        download_file 'https://raw.githubusercontent.com/Homebrew/install/7a3f48c7e498d7df3237fd41c30f4d492857edf4/install.sh' "$MAC_WORK/homebrew.sh"
        NONINTERACTIVE=1 /bin/bash "$MAC_WORK/homebrew.sh"
    fi
    [[ -x $BREW ]] || die "Homebrew was not installed at $BREW"
    export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"
    "$BREW" install "${FORMULAE[@]}"
    if ((${#CASKS[@]})); then "$BREW" install --cask "${CASKS[@]}"; fi
}

macos_preferences() {
    local file domain backup
    backup=$(mktemp -d "$HOME/Library/Preferences/dotfiles-backup.XXXXXX")
    for file in "$INSTALL_ROOT"/os/resources/macos/app-preferences/*.plist; do
        [[ -f $file ]] || continue
        domain=$(basename "$file" .plist)
        if defaults read "$domain" >/dev/null 2>&1; then defaults export "$domain" "$backup/$domain.plist"; fi
        defaults import "$domain" "$file"
    done
    defaults export NSGlobalDomain "$backup/NSGlobalDomain.plist"
    defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
    log "Previous preferences saved to $backup. Restart affected apps to load changes."
}

macos_main() (
    installer_init
    parse_options "$@"
    if [[ $SHOW_HELP == true ]]; then
        installer_usage
        macos_groups
        log "Groups: ${GROUP_IDS[*]}"
        return 0
    fi
    [[ -z $NEW_SSH_PORT && -z $NEW_HOSTNAME && $REBOOT == false && $UPGRADE == false ]] || die 'SSH ports, hostname, reboot and system upgrades are Linux-only options.'
    macos_groups
    select_groups
    macos_packages
    ADMIN_USER=${ADMIN_USER:-${SUDO_USER:-$(id -un)}}
    print_plan macos
    log "Homebrew formulae: ${FORMULAE[*]}; casks: ${CASKS[*]:-none}"
    if [[ $DRY_RUN == true ]]; then return 0; fi
    [[ $(uname -s) == Darwin ]] || die 'This installer requires macOS.'
    [[ $EUID != 0 ]] || die 'Run the macOS installer as the target user without sudo.'
    [[ $ADMIN_USER == "$(id -un)" ]] || die 'Run the installer while signed in as the target user.'
    if [[ -n $PUBLIC_SSH_KEY ]]; then validate_public_key "$PUBLIC_SSH_KEY"; fi
    confirm 'Apply this installation plan?' yes || die 'Installation cancelled.'
    MAC_WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-macos.XXXXXX")
    trap 'rm -rf "$MAC_WORK"' EXIT
    macos_brew
    local bundle='' repo
    repo=$(cd "$INSTALL_ROOT/.." && pwd)
    if [[ -f $INSTALL_ROOT/source.bundle && $DOTFILES_REF == main ]]; then
        bundle="$INSTALL_ROOT/source.bundle"
    elif [[ -e $repo/.git && $DOTFILES_REF == main ]]; then
        git -C "$repo" bundle create "$MAC_WORK/dotfiles.bundle" HEAD
        bundle="$MAC_WORK/dotfiles.bundle"
    fi
    /bin/bash "$INSTALL_ROOT/lib/user.sh" "$DOTFILES_REF" "$SKIP_PLUGINS" "$PUBLIC_SSH_KEY" "$bundle"
    if group_selected core; then
        /bin/bash "$INSTALL_ROOT/os/resources/macos/scripts/symlink-gnubin-brew-packages"
    fi
    if group_selected essentials; then
        # Configure Fish persistently without sourcing the user's existing startup files.
        # shellcheck disable=SC2016
        "$BREW_PREFIX/bin/fish" --no-config -c 'fish_add_path -U $argv' -- "$BREW_PREFIX/bin" "$BREW_PREFIX/sbin"
        if group_selected core; then
            # shellcheck disable=SC2016
            "$BREW_PREFIX/bin/fish" --no-config -c 'fish_add_path -U $argv' -- "$HOME/.local/share/dotfiles/gnubin"
        fi
        if [[ $CHANGE_SHELL == true ]]; then
            if ! grep -Fqx "$BREW_PREFIX/bin/fish" /etc/shells; then
                printf '%s\n' "$BREW_PREFIX/bin/fish" | sudo tee -a /etc/shells >/dev/null
            fi
            sudo chsh -s "$BREW_PREFIX/bin/fish" "$ADMIN_USER"
        fi
    fi
    if group_selected preferences; then macos_preferences; fi
    log 'Installation completed successfully.'
)
