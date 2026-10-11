#!/usr/bin/env bash
# Run only as the account whose files are being installed, never through a login shell.
# shellcheck source=install/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

clone_dependency() {
    local url=$1 ref=$2 destination=$3
    if [[ -e $destination ]]; then
        [[ -d $destination/.git ]] || die "Expected a Git checkout: $destination"
        log "Preserving existing checkout: $destination"
        return 0
    fi
    mkdir -p "$(dirname "$destination")"
    git init -q "$destination"
    git -C "$destination" remote add origin "$url"
    if ! git -C "$destination" fetch --depth=1 origin "$ref"; then
        # Keep the failed checkout for diagnosis; never delete an existing checkout.
        die "Could not fetch $url at $ref; incomplete checkout: $destination"
    fi
    git -C "$destination" checkout -q --detach FETCH_HEAD
}

backup_and_link_dotfiles() {
    local castle=$1 source relative target parent backup_root='' manifest
    [[ -d $castle/home ]] || die "Missing home directory in $castle"
    manifest=$(mktemp "$USER_WORK/files.XXXXXX")
    find "$castle/home" \( -type f -o -type l \) -print0 >"$manifest"
    while IFS= read -r -d '' source; do
        relative=${source#"$castle/home/"}
        target="$HOME/$relative"
        parent=$(dirname "$target")
        # Do not traverse a symlinked parent and accidentally modify another tree.
        while [[ $parent != "$HOME" ]]; do
            [[ $parent == "$HOME/"* ]] || die 'Dotfile path escapes the home directory.'
            [[ ! -L $parent ]] || die "Refusing to traverse symlinked directory: $parent"
            [[ ! -e $parent || -d $parent ]] || die "Expected a directory: $parent"
            parent=$(dirname "$parent")
        done
        if [[ -L $target && $(readlink "$target") == "$source" ]]; then continue; fi
        if [[ -e $target || -L $target ]]; then
            if [[ -z $backup_root ]]; then
                mkdir -p "$HOME/.local/state/dotfiles/backups"
                backup_root=$(mktemp -d "$HOME/.local/state/dotfiles/backups/install.XXXXXX")
                log "Backing up conflicting files to $backup_root"
            fi
            mkdir -p "$backup_root/$(dirname "$relative")"
            mv "$target" "$backup_root/$relative"
        fi
        mkdir -p "$(dirname "$target")"
        ln -s "$source" "$target"
    done <"$manifest"
    rm -f "$manifest"
}

authorize_key() {
    local key=$1 authorized="$HOME/.ssh/authorized_keys" key_type key_body ignored
    [[ ! -L $HOME/.ssh && ! -L $authorized ]] || die 'Refusing to modify a symlinked SSH directory or authorized_keys.'
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$authorized"
    chmod 600 "$authorized"
    # shellcheck disable=SC2034
    read -r key_type key_body ignored <<<"$key"
    # Match key material even if a previous line has a different comment or restrictions.
    if ! awk -v kind="$key_type" -v body="$key_body" '
        { for (i = 1; i < NF; i++) if ($i == kind && $(i+1) == body) found=1 }
        END { exit !found }' "$authorized"; then
        # A leading newline also handles an existing file without a final newline.
        printf '\n%s\n' "$key" >>"$authorized"
    fi
}

install_user_plugins() {
    local timeout_bin
    timeout_bin=$(command -v timeout || command -v gtimeout) || die 'Plugin installation needs timeout (coreutils).'
    export GIT_TERMINAL_PROMPT=0
    if command -v fish >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/fish/functions"
        if [[ ! -f $HOME/.config/fish/functions/fisher.fish ]]; then
            download_file 'https://raw.githubusercontent.com/jorgebucaran/fisher/791da644d33d392216f6b1a9b5fc1e470db6d7f2/functions/fisher.fish' "$USER_WORK/fisher.fish"
            cp "$USER_WORK/fisher.fish" "$HOME/.config/fish/functions/fisher.fish"
        fi
        # Expanded by Fish in the target account, not by the provisioning shell.
        # shellcheck disable=SC2016
        "$timeout_bin" 10m fish --no-config -c 'source "$HOME/.config/fish/functions/fisher.fish"; fisher update'
    fi
    if command -v vim >/dev/null 2>&1; then
        clone_dependency https://github.com/VundleVim/Vundle.vim.git 5548a1a937d4e72606520c7484cd384e6c76b565 "$HOME/.vim/bundle/vundle"
        "$timeout_bin" 10m vim -n -es -i NONE -u "$HOME/.vimrc" -c 'set nomore' -c PluginInstall -c qall </dev/null
    fi
    if command -v tmux >/dev/null 2>&1; then
        clone_dependency https://github.com/tmux-plugins/tpm.git e261deb1b47614eed3400089ce7197dc68acc4eb "$HOME/.tmux/plugins/tpm"
        # TPM reads the config itself; use a private server, leaving existing sessions alone.
        TMUX_SOCKET="dotfiles-install-$$"
        export TMUX_TMPDIR="$USER_WORK"
        tmux -L "$TMUX_SOCKET" -f /dev/null new-session -d -s install
        tmux -L "$TMUX_SOCKET" set-environment -g TMUX_PLUGIN_MANAGER_PATH "$HOME/.tmux/plugins/"
        # TPM invokes `tmux` internally. Its TMUX variable selects this private server.
        local socket_path
        socket_path=$(tmux -L "$TMUX_SOCKET" display-message -p '#{socket_path}')
        TMUX="$socket_path,0,0" "$timeout_bin" 10m bash "$HOME/.tmux/plugins/tpm/scripts/install_plugins.sh"
        tmux -L "$TMUX_SOCKET" kill-server
        TMUX_SOCKET=''
    fi
}

user_cleanup() {
    if [[ -n ${TMUX_SOCKET:-} ]]; then tmux -L "$TMUX_SOCKET" kill-server >/dev/null 2>&1 || true; fi
    if [[ -n ${USER_WORK:-} ]]; then rm -rf "$USER_WORK"; fi
}

user_main() {
    installer_init
    local ref=$1 skip_plugins=$2 key=$3 bundle=${4:-} castle="$HOME/.homesick/repos/dotfiles"
    [[ -d $HOME && $HOME != / ]] || die 'Invalid target home directory.'
    # sudo changes identity and HOME, but can leave an inaccessible caller working directory.
    cd "$HOME"
    umask 077
    USER_WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-user-work.XXXXXX")
    trap user_cleanup EXIT
    export GIT_TERMINAL_PROMPT=0
    mkdir -p "$HOME/.homesick/repos"
    clone_dependency https://github.com/andsens/homeshick.git 9768486e513523b1a3f7d3e44954e65eb2f6b979 "$HOME/.homesick/repos/homeshick"
    if [[ -e $castle ]]; then
        [[ -d $castle/.git ]] || die "Expected an existing Git checkout at $castle"
        log "Preserving existing dotfiles checkout, including local changes: $castle"
    elif [[ -n $bundle ]]; then
        git clone "$bundle" "$castle"
        git -C "$castle" remote set-url origin https://github.com/mamiu/dotfiles.git
    else
        clone_dependency https://github.com/mamiu/dotfiles.git "$ref" "$castle"
    fi
    backup_and_link_dotfiles "$castle"
    if [[ -n $key ]]; then authorize_key "$key"; fi
    if [[ $skip_plugins != true ]]; then install_user_plugins; fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then user_main "$@"; fi
