#!/usr/bin/env bash

# helper variables to make text bold
bold_start=$(tput bold)
bold_end=$(tput sgr0)

if [ "$EUID" -ne 0 ]; then
    echo "Installation script has to be called with root permissions!"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MULTISELECT_SCRIPT="$INSTALL_DIR/utils/multiselect.sh"
MULTISELECT_URL="https://raw.githubusercontent.com/paulmiu/dotfiles/master/install/utils/multiselect.sh"
MULTISELECT_AVAILABLE=false

download_file() {
    local url=$1
    local output_file=$2

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$output_file"
    elif command -v wget &>/dev/null; then
        wget -qO "$output_file" "$url"
    else
        echo "Could not download $url because curl and wget are both missing." >&2
        return 1
    fi
}

bash_supports_nameref() {
    (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) ))
}

if bash_supports_nameref; then
    if [ -f "$MULTISELECT_SCRIPT" ]; then
        # shellcheck source=../utils/multiselect.sh disable=SC1091
        source "$MULTISELECT_SCRIPT"
        MULTISELECT_AVAILABLE=true
    else
        MULTISELECT_TMP="$(mktemp)"
        if download_file "$MULTISELECT_URL" "$MULTISELECT_TMP"; then
            # shellcheck source=/dev/null
            source "$MULTISELECT_TMP"
            MULTISELECT_AVAILABLE=true
            rm -f "$MULTISELECT_TMP"
        else
            rm -f "$MULTISELECT_TMP"
            echo "Could not download multiselect helper from $MULTISELECT_URL; falling back to yes/no prompts." >&2
        fi
    fi
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -u|--admin-user)
            if [ -z "$2" ]; then
                echo "You must pass a target user as second argument to -u or --admin-user!" >&2
                exit 1
            fi
            TARGET_USER="$2"
            shift 2
        ;;
        --admin-user=*)
            TARGET_USER="${1#*=}"
            shift
        ;;
        -n|--nickname)
            if [ -z "$2" ]; then
                echo "You must pass a nickname as second argument to -n or --nickname!" >&2
                exit 1
            fi
            # Parsed for compatibility with install.sh; macOS does not use the remote-host nickname.
            # shellcheck disable=SC2034
            NICKNAME="$2"
            shift 2
        ;;
        --nickname=*)
            # Parsed for compatibility with install.sh; macOS does not use the remote-host nickname.
            # shellcheck disable=SC2034
            NICKNAME="${1#*=}"
            shift
        ;;
        -k|--add-ssh-key)
            if [ -z "$2" ]; then
                echo "You must pass a public SSH key as second argument to -k or --add-ssh-key!" >&2
                exit 1
            fi
            PUBLIC_SSH_KEY="$2"
            shift 2
        ;;
        --add-ssh-key=*)
            PUBLIC_SSH_KEY="${1#*=}"
            shift
        ;;
        -p|--new-ssh-port)
            if [ -z "$2" ]; then
                echo "You must pass a port number as second argument to -p or --new-ssh-port!" >&2
                exit 1
            fi
            # Parsed for compatibility with install.sh; macOS does not reconfigure sshd here.
            # shellcheck disable=SC2034
            NEW_SSH_PORT="$2"
            shift 2
        ;;
        --new-ssh-port=*)
            # Parsed for compatibility with install.sh; macOS does not reconfigure sshd here.
            # shellcheck disable=SC2034
            NEW_SSH_PORT="${1#*=}"
            shift
        ;;
        -r|--reboot)
            # Parsed for compatibility with install.sh; macOS installs are not rebooted automatically.
            # shellcheck disable=SC2034
            REBOOT_AFTER_INSTALLATION=true
            shift
        ;;
        *)
            if [ "${1// }" ]; then
                echo "unknown option: $1" >&2
                exit 1
            fi
            shift
        ;;
    esac
done

user_exists() {
    local target_user=$1
    local existing_user

    for existing_user in "${all_users[@]}"; do
        if [ "$existing_user" = "$target_user" ]; then
            return 0
        fi
    done

    return 1
}

all_users=()
while IFS= read -r user_name; do
    all_users+=( "$user_name" )
done < <(dscl . list /Users | grep -v '^_')

if [ "$TARGET_USER" ] && ! user_exists "$TARGET_USER"; then
    echo "Could not find the specified user $TARGET_USER on this system."

    read -r -p "Do you want to install ${bold_start}paulmiu/dotfiles${bold_end} for another user? [${bold_start}Y${bold_end}/n] " install_for_other_user </dev/tty
    [ -z "$install_for_other_user" ] && install_for_other_user="y"
    case "${install_for_other_user:0:1}" in
        y|Y )
            install_for_other_user=true
        ;;
        * )
            echo "Abort installation"
            exit 1
        ;;
    esac
fi

if [ -z "$TARGET_USER" ] || [ "$install_for_other_user" == "true" ]; then

    system_users=("daemon" "nobody" "root")

    for system_user in "${system_users[@]}"; do
        for idx in "${!all_users[@]}"; do
            if [[ ${all_users[idx]} = "$system_user" ]]; then
                unset 'all_users[idx]'
            fi
        done
    done

    number_of_users=${#all_users[@]}

    if (( number_of_users == 0 )); then
        echo "Couldn't find any user on this system"
        exit 1
    elif (( number_of_users == 1 )); then
        for user_name in "${all_users[@]}"; do
            TARGET_USER="$user_name"
        done
        echo "Only user ${bold_start}${TARGET_USER}${bold_end} was found on this macOS system."
    else
        echo "Choose a user account where you want to install the dotfiles:"

        select user_option in "${all_users[@]}"
        do
            if [[ "$REPLY" =~ ^[1-9]+$ ]]; then
                if [ "$REPLY" -le ${#all_users[@]} ]; then
                    TARGET_USER="$user_option"
                    break;
                else
                    echo "Incorrect Input: Select a number 1-${#all_users[@]}"
                fi
            else
                echo "Incorrect Input: Select a number 1-${#all_users[@]}"
            fi
        done </dev/tty || user_option="1"
    fi
fi

# Confirm if dotfiles should be installed in TARGET_USER account
read -r -p "Do you really want to install ${bold_start}paulmiu/dotfiles${bold_end} for the user ${bold_start}${TARGET_USER}${bold_end}? [${bold_start}Y${bold_end}/n] " installation_confirmation </dev/tty
[ -z "$installation_confirmation" ] && installation_confirmation="y"
case "${installation_confirmation:0:1}" in
    y|Y )
        echo
        echo "Starting installation of the most basic macOS dependencies..."
    ;;
    * )
        echo "Abort installation"
        exit 1
    ;;
esac

TARGET_USER_HOME="$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | awk '{print $2; exit}')"

detect_homebrew_bin_dir() {
    if [ -x /opt/homebrew/bin/brew ]; then
        echo "/opt/homebrew/bin"
    elif [ -x /usr/local/bin/brew ]; then
        echo "/usr/local/bin"
    elif [ "$(uname -m)" = "arm64" ]; then
        echo "/opt/homebrew/bin"
    else
        echo "/usr/local/bin"
    fi
}

HOMEBREW_BIN_DIR="$(detect_homebrew_bin_dir)"
HOMEBREW_PREFIX="${HOMEBREW_BIN_DIR%/bin}"
BREW="$HOMEBREW_BIN_DIR/brew"
PATH="$HOMEBREW_BIN_DIR:$PATH"
export PATH

run_as_target_user() {
    sudo -Hu "$TARGET_USER" "$@"
}

# Install homebrew if it's not installed already
if ! run_as_target_user "$BREW" --help &>/dev/null; then
    if ! run_as_target_user /usr/bin/env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        echo -e "\nHomebrew installation failed. Check the log or try again later." >&2
        exit 1
    fi
fi

# Add Homebrew binaries as first line to /etc/paths
if ! grep -Fxq "$HOMEBREW_BIN_DIR" /etc/paths; then
    escaped_homebrew_bin_dir=${HOMEBREW_BIN_DIR//\//\\/}
    sed -i '' "1s/^/${escaped_homebrew_bin_dir}\\
/" /etc/paths
fi

add_selected_brew_packages() {
    SELECTED_BREW_PACKAGES+=("$@")
}

add_selected_brew_casks() {
    SELECTED_BREW_CASKS+=("$@")
}

choose_tools_with_yes_no_prompts() {
    local idx
    local default_answer
    local answer

    selected_tool_groups=()
    for idx in "${!tool_groups[@]}"; do
        if [[ ${tool_group_defaults[idx]} == "true" ]]; then
            default_answer="Y/n"
        else
            default_answer="y/N"
        fi

        read -r -p "Install ${tool_groups[idx]}? [$default_answer] " answer </dev/tty
        if [ -z "$answer" ]; then
            selected_tool_groups[idx]="${tool_group_defaults[idx]}"
        else
            case "${answer:0:1}" in
                y|Y )
                    selected_tool_groups[idx]="true"
                ;;
                * )
                    selected_tool_groups[idx]="false"
                ;;
            esac
        fi
    done
}

choose_tools_to_install() {
    tool_groups=(
        "GNU/core command-line tools"
        "Dotfiles essentials (mosh, git, fish, tmux, vim, fzf, bat, fd, ripgrep, jq)"
        "Terminal UI tools (ncdu, htop, nnn, tig)"
        "Developer shell tools (reattach-to-user-namespace, shellcheck, shfmt)"
        "Misc media and network tools (libpq, ffmpeg, tree, pipenv, deno, rclone, sshuttle, youtube-dl)"
        "Kubernetes tools (kubectl, helm, kubectx, k9s, k3d, velero)"
        "GUI apps (iTerm2)"
    )
    # Used by multiselect through a nameref.
    # shellcheck disable=SC2034
    tool_group_defaults=(
        "true"
        "true"
        "true"
        "true"
        "true"
        "false"
        "true"
    )
    selected_tool_groups=()

    echo
    echo "Choose which tool groups should be installed:"
    if [ "$MULTISELECT_AVAILABLE" == "true" ]; then
        multiselect "true" selected_tool_groups tool_groups tool_group_defaults </dev/tty
    else
        choose_tools_with_yes_no_prompts
    fi

    echo "Selected tool groups:"
    selected_tool_group_count=0
    for idx in "${!tool_groups[@]}"; do
        if [[ ${selected_tool_groups[idx]} == "true" ]]; then
            echo "  - ${tool_groups[idx]}"
            selected_tool_group_count=$((selected_tool_group_count + 1))
        fi
    done
    if (( selected_tool_group_count == 0 )); then
        echo "  - none"
    fi

    SELECTED_BREW_PACKAGES=()
    SELECTED_BREW_CASKS=()

    for idx in "${!tool_groups[@]}"; do
        if [[ ${selected_tool_groups[idx]} != "true" ]]; then
            continue
        fi

        case "$idx" in
            0)
                add_selected_brew_packages coreutils binutils diffutils findutils gnu-getopt gawk gnutls grep gnu-sed gnu-tar gzip gnu-indent gnu-which gnu-time less python bash openssh p7zip rsync wget netcat wdiff unzip watch
            ;;
            1)
                add_selected_brew_packages mosh git fish tmux vim fzf bat fd ripgrep jq gpg nmap
            ;;
            2)
                add_selected_brew_packages ncdu htop nnn tig
            ;;
            3)
                add_selected_brew_packages reattach-to-user-namespace shellcheck shfmt
            ;;
            4)
                add_selected_brew_packages libpq ffmpeg tree pipenv deno rclone sshuttle youtube-dl
            ;;
            5)
                add_selected_brew_packages kubernetes-cli helm kubectx k9s k3d velero
            ;;
            6)
                add_selected_brew_casks iterm2
            ;;
        esac
    done
}

brew_install_packages() {
    choose_tools_to_install

    if [ ${#SELECTED_BREW_PACKAGES[@]} -gt 0 ]; then
        echo "Installing Homebrew packages: ${SELECTED_BREW_PACKAGES[*]}"
        run_as_target_user "$BREW" install "${SELECTED_BREW_PACKAGES[@]}"
    else
        echo "No Homebrew packages selected."
    fi

    if [ ${#SELECTED_BREW_CASKS[@]} -gt 0 ]; then
        echo "Installing Homebrew casks: ${SELECTED_BREW_CASKS[*]}"
        run_as_target_user "$BREW" install --cask "${SELECTED_BREW_CASKS[@]}"
    else
        echo "No Homebrew casks selected."
    fi
}

install_fisher_plugins() {
    if ! command -v curl &>/dev/null; then
        echo "Skipping fisher because curl is not installed."
        return 0
    fi

    if ! command -v fish &>/dev/null; then
        echo "Skipping fisher because fish is not installed."
        return 0
    fi

    run_as_target_user fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher && fisher update"
}

install_vim_plugins() {
    local vim_plugin_marker
    local vim_plugin_status
    local timeout_cmd=""
    local -a vim_plugin_command

    if ! command -v vim &>/dev/null; then
        echo "Skipping Vim plugins because Vim is not installed."
        return 0
    fi

    if ! command -v git &>/dev/null; then
        echo "Skipping Vim plugins because git is not installed."
        return 0
    fi

    vim_plugin_marker="$TARGET_USER_HOME/.vim/bundle/.dotfiles_plugins_installed"
    if [ -f "$vim_plugin_marker" ]; then
        return 0
    fi

    run_as_target_user mkdir -p "$TARGET_USER_HOME/.vim/bundle"

    if [ ! -f "$TARGET_USER_HOME/.vim/bundle/vundle/autoload/vundle.vim" ]; then
        rm -rf "$TARGET_USER_HOME/.vim/bundle/vundle"
        if ! run_as_target_user git clone https://github.com/VundleVim/Vundle.vim.git "$TARGET_USER_HOME/.vim/bundle/vundle"; then
            echo "Skipping Vim plugins because Vundle could not be installed."
            return 0
        fi
    fi

    echo "Installing Vim plugins with a 10 minute timeout..."
    vim_plugin_command=(vim -n -es -i NONE -u "$TARGET_USER_HOME/.vimrc" -c "set nomore" -c "PluginInstall" -c "qall")

    if command -v gtimeout &>/dev/null; then
        timeout_cmd="$(command -v gtimeout)"
    elif command -v timeout &>/dev/null; then
        timeout_cmd="$(command -v timeout)"
    fi

    if [ "$timeout_cmd" ]; then
        run_as_target_user "$timeout_cmd" 10m "${vim_plugin_command[@]}" </dev/null &>/dev/null
        vim_plugin_status=$?
        if (( vim_plugin_status == 124 )); then
            echo "Skipping remaining Vim plugin setup because it timed out."
            return 0
        elif (( vim_plugin_status != 0 )); then
            echo "Skipping remaining Vim plugin setup because PluginInstall failed."
            return 0
        fi
    elif ! run_as_target_user "${vim_plugin_command[@]}" </dev/null &>/dev/null; then
        echo "Skipping remaining Vim plugin setup because PluginInstall failed."
        return 0
    fi

    run_as_target_user touch "$vim_plugin_marker"
}

brew_install_packages

# Create the Homebrew binaries folder if it doesn't exist yet
if [ ! -d "$HOMEBREW_BIN_DIR" ]; then
    mkdir -p "$HOMEBREW_BIN_DIR"
    chown -R "$TARGET_USER:admin" "$HOMEBREW_BIN_DIR/"
fi

while IFS= read -r gnuutil; do
    run_as_target_user ln -fs "$gnuutil" "$HOMEBREW_BIN_DIR/"
done < <(find "$HOMEBREW_PREFIX" -path '*/libexec/gnubin/*' -type f 2>/dev/null)

while IFS= read -r pybin; do
    run_as_target_user ln -fs "$pybin" "$HOMEBREW_BIN_DIR/"
done < <(find "$HOMEBREW_PREFIX" -path '*/python/libexec/bin/*' -type f 2>/dev/null)

if ! command -v git &>/dev/null; then
    echo "Skipping dotfiles setup because git is not installed."
else
    # Download homeshick
    if [ ! -d "$TARGET_USER_HOME/.homesick/repos/homeshick" ]; then
        run_as_target_user git clone https://github.com/andsens/homeshick.git "$TARGET_USER_HOME/.homesick/repos/homeshick"
    fi

    # Download and install dotfiles
    if [ -d "$TARGET_USER_HOME/.homesick/repos/dotfiles" ]; then
        echo "There's already a dotfiles repository in the '~/.homesick/repos/' directory."
        echo "Dotfiles installation is cancelled."
        exit 1
    fi
    run_as_target_user "$TARGET_USER_HOME/.homesick/repos/homeshick/bin/homeshick" clone -b paulmiu/dotfiles
    run_as_target_user "$TARGET_USER_HOME/.homesick/repos/homeshick/bin/homeshick" link -f dotfiles

    # Backup property list files in case they exist and copy the new files to the app preferences folder
    app_preferences_path="$TARGET_USER_HOME/.homesick/repos/dotfiles/install/os/resources/macos/app-preferences"
    if [ -d "$app_preferences_path" ]; then
        for file in "$app_preferences_path"/*
        do
            [ -e "$file" ] || continue
            plist_filename=$(basename "$file")
            plist_dir_path="$TARGET_USER_HOME/Library/Preferences"
            plist_file_path="$plist_dir_path/$plist_filename"
            if [ -f "$plist_file_path" ]; then
                mv "$plist_file_path" "${plist_file_path}_backup"
            fi
            cp "$app_preferences_path/$plist_filename" "$plist_dir_path/"
        done
    fi
fi

# Make fish the default shell
if command -v fish &>/dev/null; then
    fish_path="$(command -v fish)"
    if ! grep -Fxq "$fish_path" /etc/shells; then
        echo "$fish_path" >> /etc/shells
    fi
    chsh -s "$fish_path" "$TARGET_USER"
else
    echo "Skipping fish as default shell because fish is not installed."
fi

# Generate ssh key pair
if [ ! -d "$TARGET_USER_HOME/.ssh" ]; then
    run_as_target_user mkdir "$TARGET_USER_HOME/.ssh"
fi
if [ ! -f "$TARGET_USER_HOME/.ssh/id_rsa" ]; then
    run_as_target_user ssh-keygen -b 2048 -t rsa -f "$TARGET_USER_HOME/.ssh/id_rsa" -q -N ""
fi
chmod 700 "$TARGET_USER_HOME/.ssh"
find "$TARGET_USER_HOME/.ssh" -type f ! -name '*.pub' -exec chmod 600 {} +
find "$TARGET_USER_HOME/.ssh" -type f -name '*.pub' -exec chmod 644 {} +

if [ "$PUBLIC_SSH_KEY" ]; then
    echo "$PUBLIC_SSH_KEY" >> "$TARGET_USER_HOME/.ssh/authorized_keys"
    chown "$TARGET_USER:staff" "$TARGET_USER_HOME/.ssh/authorized_keys"
fi

# Install fisher - a package manager for the fish shell
if [ ! -f "$TARGET_USER_HOME/.config/fish/functions/fisher.fish" ]; then
    install_fisher_plugins
fi

# Install vim plugins
install_vim_plugins

# Install tmux plugin manager and tmux plugins
if [ ! -d "$TARGET_USER_HOME/.tmux/plugins/tpm" ]; then
    if command -v tmux &>/dev/null; then
        run_as_target_user git clone https://github.com/tmux-plugins/tpm "$TARGET_USER_HOME/.tmux/plugins/tpm"
        run_as_target_user tmux new-session -s "$TARGET_USER" -d "$TARGET_USER_HOME/.tmux/plugins/tpm/tpm && $TARGET_USER_HOME/.tmux/plugins/tpm/scripts/install_plugins.sh"
    else
        echo "Skipping tmux plugins because tmux is not installed."
    fi
fi

# Set most important defaults for developers
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -int 0
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -int 0
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -int 0

# Disable the security assessment policy subsystem
spctl --master-disable

# Download and install FiraCode font
if ! ls /Library/Fonts/FiraCode-* &>/dev/null; then
    download_file https://github.com/tonsky/FiraCode/releases/download/2/FiraCode_2.zip ./fira_code_2.zip
    unzip fira_code_2.zip -d ./fira_code_2
    chown root:wheel ./fira_code_2/otf/*
    mv ./fira_code_2/otf/* /Library/Fonts/
    rm -rf ./fira_code_2*
fi

# Done
echo
echo "All dependencies are installed successfully."
echo
echo "Now you can install the mac apps of your choice."
echo "The browser will automatically open at step 16 of this guide:"
echo "https://github.com/paulmiu/dotfiles/blob/master/install/os/macos.md"

run_as_target_user open "https://github.com/paulmiu/dotfiles/blob/master/install/os/macos.md#16-install-mac-apps-only-the-ones-you-really-need"
