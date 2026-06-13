#!/usr/bin/env bash

# enable recursive globbing
shopt -s globstar

# helper variables to make text bold
bold_start=$(tput bold)
bold_end=$(tput sgr0)

if [ $EUID != 0 ]; then
    echo "Installation script has to be called with root permissions!"
    exit 1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -u)
            if [ -z "$2" ]; then
                shift
            fi
            TARGET_USER="$2"
            shift 2
        ;;
        # call this parameter admin user to make it compatible with the other installation scripts
        --admin-user=*)
            TARGET_USER="${1#*=}"
            shift
        ;;
        -k)
            PUBLIC_SSH_KEY="$2"
            shift 2
        ;;
        --add-ssh-key=*)
            PUBLIC_SSH_KEY="${1#*=}"
            shift
        ;;
        -p)
            NEW_SSH_PORT="$2"
            shift 2
        ;;
        --new-ssh-port=*)
            NEW_SSH_PORT="${1#*=}"
            shift
        ;;
        *)
            if [ "${1// }" ]; then
                echo "unknown option: $1" >&2
            fi
            shift
        ;;
    esac
done

all_users=()
while IFS= read -r line; do
    all_users+=( "$line" )
done < <( dscl . list /Users | grep -v '^_' )

if [ "$TARGET_USER" ] && [[ ! " ${all_users[@]} " =~ " ${TARGET_USER} " ]]; then
    echo "Could not find the specified user $TARGET_USER on this system."

    read -p "Do you want to install ${bold_start}paulmiu/dotfiles${bold_end} for another user? [${bold_start}Y${bold_end}/n] " install_for_other_user </dev/tty
    [ -z "$install_for_other_user" ] && install_for_other_user="y"
    case "${install_for_other_user:0:1}" in
        y|Y )
            install_for_other_user=true
        ;;
        * )
            echo Abort installation
            exit 1
        ;;
    esac
fi

if [ -z "$TARGET_USER" ] || [ "$install_for_other_user" == "true" ]; then

    system_users=("daemon" "nobody" "root")

    for target in "${system_users[@]}"; do
        for i in "${!all_users[@]}"; do
            if [[ ${all_users[i]} = $target ]]; then
                unset 'all_users[i]'
            fi
        done
    done

    number_of_users=${#all_users[@]}

    if (( number_of_users == 0 )); then
        echo Couldn\'t find any user on this system
        exit 1
    elif (( number_of_users == 1 )); then
        for element in ${all_users[@]}; do
            user="$element"
        done
        TARGET_USER="$user"
        echo "Only user ${bold_start}${TARGET_USER}${bold_end} was found on this macOS system."
    else
        echo Choose a user account where you want to install the dotfiles:

        select user_option in "${all_users[@]}"
        do
            if [[ "$REPLY" =~ ^[1-9]+$ ]]; then
                if [ $REPLY -le ${#all_users[@]} ]; then
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
read -p "Do you really want to install ${bold_start}paulmiu/dotfiles${bold_end} for the user ${bold_start}${TARGET_USER}${bold_end}? [${bold_start}Y${bold_end}/n] " installation_confirmation </dev/tty
[ -z "$installation_confirmation" ] && installation_confirmation="y"
case "${installation_confirmation:0:1}" in
    y|Y )
        echo
        echo "Starting installation of the most basic macOS dependencies..."
    ;;
    * )
        echo Abort installation
        exit 1
    ;;
esac

TARGET_USER_HOME=$(su - $TARGET_USER -c 'echo $HOME')
HOMEBREW_BIN_DIR="/opt/homebrew/bin"

# Install homebrew if it's not installed already
if ! { sudo -Hu $TARGET_USER brew --help &>/dev/null; }; then
    sudo -Hu $TARGET_USER /usr/bin/env bash -c "NONINTERACTIVE=1 $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    PATH=$HOMEBREW_BIN_DIR:$PATH
    export PATH

    if [[ $? -gt 0 ]]; then
        echo -e "\nHomebrew installation failed. Check the log or try again later." >&2
        exit 1
    fi
fi

# Add /usr/local/gnubin as first line to /etc/paths
if ! grep -Fxq "$HOMEBREW_BIN_DIR" /etc/paths; then
    sed -i '' '1s/^/\/opt\/homebrew\/bin\'$'\n/' /etc/paths
fi

# Install brew packages
# GNU utils (minimum requirements)
sudo -Hu $TARGET_USER brew install coreutils binutils diffutils findutils gnu-getopt gawk gnutls grep gnu-sed gnu-tar gzip gnu-indent gnu-which gnu-time less python bash openssh p7zip rsync wget netcat wdiff unzip watch
# dependencies for the full experience of the paulmiu dotfiles setup (highly recommended)
sudo -Hu $TARGET_USER brew install mosh git fish tmux vim fzf bat fd ripgrep jq gpg nmap reattach-to-user-namespace shellcheck shfmt
# TUI tools (cli tools that provide a terminal or text-based user interface) (recommended)
sudo -Hu $TARGET_USER brew install ncdu htop nnn tig
# kubernetes cli tools (only if kubernetes tools are needed)
sudo -Hu $TARGET_USER brew install kubernetes-cli helm kubectx k9s k3d velero
# misc nice-to-have cli tools (optional)
sudo -Hu $TARGET_USER brew install libpq ffmpeg tree pipenv deno rclone sshuttle youtube-dl
# macOS GUI apps
sudo -Hu $TARGET_USER brew install --cask iterm2

# Create the Homebrew binaries folder if it doesn't exist yet
if [ ! -d "$HOMEBREW_BIN_DIR" ]; then
    mkdir -p "$HOMEBREW_BIN_DIR"
    chown -R $TARGET_USER:admin "$HOMEBREW_BIN_DIR/"
fi

for gnuutil in /opt/homebrew/**/libexec/gnubin/*; do
  sudo -Hu $TARGET_USER ln -fs "$gnuutil" "$HOMEBREW_BIN_DIR/"
done

for pybin in /opt/homebrew/**/python/libexec/bin/*; do
  sudo -Hu $TARGET_USER ln -fs "$pybin" "$HOMEBREW_BIN_DIR/"
done

# Download homeshick
if [ ! -d "$TARGET_USER_HOME/.homesick/repos/homeshick" ]; then
    sudo -Hu $TARGET_USER git clone https://github.com/andsens/homeshick.git "$TARGET_USER_HOME/.homesick/repos/homeshick"
fi

# Download and install dotfiles
if [ -d "$TARGET_USER_HOME/.homesick/repos/dotfiles" ]; then
    echo "There's already a dotfiles repository in the '~/.homesick/repos/' directory."
    echo "Dotfiles installation is cancelled."
    exit 1
fi
sudo -Hu $TARGET_USER "$TARGET_USER_HOME/.homesick/repos/homeshick/bin/homeshick" clone -b paulmiu/dotfiles
sudo -Hu $TARGET_USER "$TARGET_USER_HOME/.homesick/repos/homeshick/bin/homeshick" link -f dotfiles

# Backup property list files in case they exist and copy the new files to the app preferences folder
app_preferences_path="$TARGET_USER_HOME/.homesick/repos/dotfiles/install/os/resources/macos/app-preferences"
for file in $app_preferences_path/*
do
    plist_filename=$(basename "$file")
    plist_dir_path="$TARGET_USER_HOME/Library/Preferences"
    plist_file_path="$plist_dir_path/$plist_filename"
    if [ -f "$plist_file_path" ]; then
        mv "$plist_file_path" "${plist_file_path}_backup"
    fi
    cp "$app_preferences_path/$plist_filename" "$plist_dir_path/"
done

# Make fish the default shell
if ! grep -Fxq "$(which fish)" /etc/shells; then
    echo $(which fish) >> /etc/shells
fi
chsh -s $(which fish) $TARGET_USER

# Generate ssh key pair
if [ ! -d "$TARGET_USER_HOME/.ssh" ]; then
    sudo -Hu $TARGET_USER mkdir "$TARGET_USER_HOME/.ssh"
fi
if [ ! -f "$TARGET_USER_HOME/.ssh/id_rsa" ]; then
    sudo -Hu $TARGET_USER ssh-keygen -b 2048 -t rsa -f "$TARGET_USER_HOME/.ssh/id_rsa" -q -N ""
fi
sudo -Hu $TARGET_USER chmod 700 $TARGET_USER_HOME/.ssh
sudo -Hu $TARGET_USER chmod 600 $TARGET_USER_HOME/.ssh/*
sudo -Hu $TARGET_USER chmod 644 $TARGET_USER_HOME/.ssh/*.pub

# Install fisher - a package manager for the fish shell
if [ ! -f "$TARGET_USER_HOME/.config/fish/functions/fisher.fish" ]; then
    sudo -Hu $TARGET_USER fish -c "curl -sL https://git.io/fisher | source && fisher update"
fi

# Install vim plugins
if [ ! -d "$TARGET_USER_HOME/.vim/bundle" ]; then
    sudo -Hu $TARGET_USER vim +PluginInstall +qall &>/dev/null
fi

# Install tmux plugin manager and tmux plugins
if [ ! -d "$TARGET_USER_HOME/.tmux/plugins/tpm" ]; then
    sudo -Hu $TARGET_USER git clone https://github.com/tmux-plugins/tpm $TARGET_USER_HOME/.tmux/plugins/tpm
    sudo -Hu $TARGET_USER tmux new-session -s "$TARGET_USER" -d "$TARGET_USER_HOME/.tmux/plugins/tpm/tpm && $TARGET_USER_HOME/.tmux/plugins/tpm/scripts/install_plugins.sh"
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
    curl -L https://github.com/tonsky/FiraCode/releases/download/2/FiraCode_2.zip -o ./fira_code_2.zip
    unzip fira_code_2.zip -d ./fira_code_2
    chown root:wheel ./fira_code_2/otf/*
    mv fira_code_2/otf/* /Library/Fonts/
    rm -rf ./fira_code_2*
fi

# Done
echo
echo "All dependencies are installed successfully."
echo
echo "Now you can install the mac apps of your choise."
echo "The browser will automatically open at step 16 of this guide:"
echo "https://github.com/paulmiu/dotfiles/blob/master/install/os/macos.md"

sudo -Hu $TARGET_USER open "https://github.com/paulmiu/dotfiles/blob/master/install/os/macos.md#16-install-mac-apps-only-the-ones-you-really-need"
