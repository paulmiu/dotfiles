# macOS setup

(If the Mac is enrolled to an enterprise device registry via the MDM ([Mobile Device Management](https://developer.apple.com/business/documentation/MDM-Protocol-Reference.pdf#//apple_ref/doc/uid/TP40017387-CH10-SW44)) then first disable the notification that this Mac needs to be enrolled, as described in [this Guide](https://gist.github.com/henrik242/65d26a7deca30bdb9828e183809690bd))

## 1. Make sure you're using bash (it's just working)

```bash
bash
```

## 2. Install homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## 3. Install selected brew package groups

```bash
# GNU/core command-line tools
brew install coreutils binutils diffutils findutils gnu-getopt gawk gnutls grep gnu-sed gnu-tar gzip gnu-indent gnu-which gnu-time less python bash openssh p7zip rsync wget netcat wdiff unzip watch

# Dotfiles essentials
brew install mosh git fish tmux vim fzf bat fd ripgrep jq gpg nmap

# Terminal UI tools
brew install ncdu htop nnn tig

# Developer shell tools
brew install reattach-to-user-namespace shellcheck shfmt

# Misc media and network tools
brew install libpq ffmpeg tree pipenv deno rclone sshuttle youtube-dl

# Kubernetes tools (disabled by default in the install script)
brew install kubernetes-cli helm kubectx k9s k3d velero

# GUI apps
brew install --cask iterm2
```

The install script asks which package groups should be installed. Kubernetes
tools are available as a separate group and are disabled by default.

## 4. Create symbolic links to all GNU binaries

```bash
HOMEBREW_PREFIX="$(brew --prefix)"
HOMEBREW_BIN_DIR="$HOMEBREW_PREFIX/bin"

find "$HOMEBREW_PREFIX" -path '*/libexec/gnubin/*' -type f -exec ln -fs {} "$HOMEBREW_BIN_DIR/" \;
find "$HOMEBREW_PREFIX" -path '*/python/libexec/bin/*' -type f -exec ln -fs {} "$HOMEBREW_BIN_DIR/" \;
```

## 5. Add Homebrew binaries as first line to /etc/paths

```bash
HOMEBREW_BIN_DIR="$(brew --prefix)/bin"
sudo sed -i '' "1s#^#$HOMEBREW_BIN_DIR\\
#" /etc/paths
```

## 6. Download dotfiles

```bash
git clone https://github.com/andsens/homeshick.git $HOME/.homesick/repos/homeshick
$HOME/.homesick/repos/homeshick/bin/homeshick clone -b paulmiu/dotfiles
```

## 7. Backup property list files in case they exist

```bash
for file in $TARGET_USER_HOME/.homesick/repos/dotfiles/home/Library/Preferences/*
do
    plist_filename=$(basename "$file")
    plist_path="$TARGET_USER_HOME/Library/Preferences/$plist_filename"
    if [ -f "$plist_path" ]; then
        cp "$plist_path" "${plist_path}_backup"
    fi
done
```

## 8. Install dotfiles

```bash
$HOME/.homesick/repos/homeshick/bin/homeshick link -f dotfiles
```

## 9. Make fish the default shell

```bash
sudo sh -c 'echo $(which fish) >> /etc/shells'
sudo chsh -s $(which fish) $USER
```

## 10. Generate ssh key pair

```bash
if [ ! -d "$HOME/.ssh" ]; then
  mkdir $HOME/.ssh
  ssh-keygen -b 2048 -t rsa -f $HOME/.ssh/id_rsa -q -N ""
fi
```

## 11. Install fisher - a package manager for the fish shell

```bash
fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher && fisher update"
```

## 12. Install vim plugins

```bash
git clone https://github.com/VundleVim/Vundle.vim.git $HOME/.vim/bundle/vundle
vim -n -es -i NONE -u "$HOME/.vimrc" -c "set nomore" -c "PluginInstall" -c "qall"
```

## 13. Install tmux plugin manager and tmux plugins

```bash
git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
tmux new-session "$HOME/.tmux/plugins/tpm/tpm && $HOME/.tmux/plugins/tpm/scripts/install_plugins.sh"
```

## 14. Disable the security assessment policy subsystem

```bash
sudo spctl --master-disable
```

## 15. Download and install FiraCode font

```bash
curl -L https://github.com/tonsky/FiraCode/releases/download/2/FiraCode_2.zip -o fira_code_2.zip
unzip fira_code_2.zip -d ./fira_code_2
sudo chown root:wheel ./fira_code_2/otf/*
sudo mv fira_code_2/otf/* /Library/Fonts/
rm -rf ./fira_code_2*
```

## 16. Install mac apps (only the ones you really need)

- Tools
  - [Clipy](https://github.com/Clipy/Clipy)
  - [ShiftIt](https://github.com/fikovnik/ShiftIt) (or [SizeUp](http://www.irradiatedsoftware.com/sizeup/))
  - [Itsycal](https://www.mowglii.com/itsycal/)
  - [MonitorControl](https://github.com/MonitorControl/MonitorControl)
  - [Bitwarden](https://bitwarden.com/)
  - [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake)
  - [Macs Fan Control (smcFanControl)](https://www.crystalidea.com/macs-fan-control)
  - [The Unarchiver](https://apps.apple.com/app/the-unarchiver/id425424353?mt=12)
  - [PDF Toolkit+ (skim)](https://apps.apple.com/app/pdf-toolkit/id545164971?mt=12)
  - [Google Drive File Stream](https://support.google.com/drive/answer/7329379) (or [Google Drive](https://www.google.com/drive/download/))
  - [TeamViewer](https://www.teamviewer.com/)
  - [Scroll Reverser](https://pilotmoon.com/scrollreverser/)
  - [Miro Video Converter](http://www.mirovideoconverter.com/)
  - [VNC Viewer (from RealVNC)](https://www.realvnc.com/de/connect/download/viewer/)
  - [AusweisApp2](https://www.ausweisapp.bund.de/ausweisapp2/)
  - [Background Music](https://github.com/kyleneideck/BackgroundMusic)
  - [(Cyberduck)](https://cyberduck.io/)
- Development
  - [VS Code](https://code.visualstudio.com/)
  - [iTerm2 (Version 3)](https://www.iterm2.com/version3.html) _Already installed with brew_
  - [Docker](https://hub.docker.com/?overlay=onboarding)
  - [Postman](https://www.getpostman.com/)
  - [Android Studio](https://developer.android.com/studio)
  - [Dash](https://kapeli.com/dash)
  - [Git Kraken](https://www.gitkraken.com/)
  - [VirtualBox](https://www.virtualbox.org/)
- Design - Video - 3D
  - [Photoshop](https://www.adobe.com/creativecloud/desktop-app.html)
  - [Lightroom](https://www.adobe.com/creativecloud/desktop-app.html)
  - [Illustrator](https://www.adobe.com/creativecloud/desktop-app.html)
  - [Premiere Pro](https://www.adobe.com/creativecloud/desktop-app.html)
  - [Blender](https://www.blender.org/)
- Browser
  - [Chrome](https://www.google.com/chrome/)
  - [Firefox](https://www.mozilla.org/firefox/)
- Communication
  - [Telegram](https://macos.telegram.org/)
  - [Skype](https://www.skype.com/)
  - [Discord](https://discordapp.com/)
- Entertainment
  - [VLC](https://www.videolan.org/)
  - [Spotify](https://www.spotify.com/)
- MS Office
  - [Office 365 for Mac](https://products.office.com/en-us/mac/microsoft-office-for-mac)
