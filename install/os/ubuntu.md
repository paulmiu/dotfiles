# Ubuntu setup

This guide is an example how to setup an Ubuntu server after a clean installation.

The automated setup script is `install/os/ubuntu.sh`. It has to be run as root.

## Automated setup

### STEP 1: Login as root user

### STEP 2: Run the setup script

```bash
bash install/os/ubuntu.sh
```

Useful options:

```bash
bash install/os/ubuntu.sh \
  --admin-user=<SERVER_USERNAME> \
  --nickname=<SERVER_NICKNAME> \
  --add-ssh-key="<PUBLIC_SSH_KEY>" \
  --new-ssh-port=<SERVER_PORT> \
  --reboot
```

The script can:

- change the current user's password
- change the hostname
- create or select an admin user
- update the system
- ask which tool groups should be installed
- install and link the dotfiles with Homeshick
- install tmux, Vim, and fish plugins
- generate an SSH key pair
- set fish as the default shell
- allow `TMUX_AUTOSTART` through SSH
- optionally change the SSH port
- optionally reboot after installation

The tool groups are selected with a multi-select prompt. Kubernetes tools are not selected by default:

```bash
Basic system tools: net-tools, gawk, uidmap
Dotfiles essentials: curl, git, vim, fish, tmux
Remote shell tools: mosh
Terminal UI tools: ncdu, htop
Search and JSON tools: fzf, bat, fd-find, ripgrep, jq
Kubernetes tools: kubectx, kubens (off by default)
```

## Manual setup

### On the server

#### STEP 1: Login as root user

#### STEP 2: Create an admin user and add it to the sudo group

If you already created an admin user account, skip this step.

```bash
adduser --disabled-password --gecos "" <SERVER_USERNAME>
passwd <SERVER_USERNAME>
adduser <SERVER_USERNAME> sudo
```

#### STEP 3: Install the most important tools

```bash
apt-get update
apt-get upgrade
apt-get dist-upgrade

apt-get install net-tools gawk uidmap
apt-get install curl git vim fish tmux mosh ncdu htop fzf bat fd-find ripgrep jq
```

#### STEP 4: Install kubectx and kubens

```bash
git clone https://github.com/ahmetb/kubectx /opt/kubectx
ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
ln -s /opt/kubectx/kubens /usr/local/bin/kubens

mkdir -p ~/.config/fish/completions
ln -s /opt/kubectx/completion/kubectx.fish ~/.config/fish/completions/
ln -s /opt/kubectx/completion/kubens.fish ~/.config/fish/completions/
```

#### STEP 5: Clone and link the dotfiles

```bash
git clone https://github.com/andsens/homeshick.git $HOME/.homesick/repos/homeshick
$HOME/.homesick/repos/homeshick/bin/homeshick clone -b paulmiu/dotfiles
$HOME/.homesick/repos/homeshick/bin/homeshick link -f dotfiles
```

#### STEP 6: Install shell, editor, and terminal plugins

```bash
git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
tmux new-session -s "$USER" -d "$HOME/.tmux/plugins/tpm/tpm && $HOME/.tmux/plugins/tpm/scripts/install_plugins.sh"

vim +PluginInstall +qall

fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher && fisher update"
```

#### STEP 7: Generate an SSH key pair

```bash
mkdir -p $HOME/.ssh
ssh-keygen -b 2048 -t rsa -f $HOME/.ssh/id_rsa -q -N ""
chmod 700 $HOME/.ssh
chmod 600 $HOME/.ssh/*
chmod 644 $HOME/.ssh/*.pub
```

#### STEP 8: Make fish the default shell

```bash
echo $(which fish) >> /etc/shells
chsh -s $(which fish)
```

#### STEP 9: Allow tmux autostart over SSH

Add the following lines to `/etc/ssh/sshd_config`:

```bash
# Allow user to pass the TMUX_AUTOSTART environment variable.
AcceptEnv TMUX_AUTOSTART
```

After that restart the SSH server:

```bash
systemctl restart ssh.service
```

#### STEP 10: Optionally change the SSH port

Set the port in `/etc/ssh/sshd_config`:

```bash
Port <SERVER_PORT>
```

On systems using `ssh.socket`, also create or update `/etc/systemd/system/ssh.socket.d/listen.conf`:

```ini
[Socket]
ListenStream=
ListenStream=<SERVER_PORT>
```

Then reload systemd and restart SSH:

```bash
systemctl daemon-reload
systemctl restart ssh.socket
```

### On the client

#### STEP 1: Setup ssh config to login easily with `ssh <SERVER_NICKNAME>`

Insert the following lines in `$HOME/.ssh/config` on the client:

```bash
Host <SERVER_NICKNAME>
  User <SERVER_USERNAME>
  HostName <SERVER_HOSTNAME>
  Port <SERVER_PORT>
  SendEnv TMUX_AUTOSTART
```

#### STEP 2: Add the client's public key to the server's authorized keys

If you have the `ssh-copy-id` command on the client:

```bash
ssh-copy-id <SERVER_NICKNAME>
```

Otherwise:

```bash
cat $HOME/.ssh/id_rsa.pub | ssh <SERVER_NICKNAME> "mkdir -p $HOME/.ssh && cat >> .ssh/authorized_keys"
```

## Variables in this guide

```bash
<SERVER_HOSTNAME> = server hostname or IP address
<SERVER_PORT> = port on the server where the SSH service is listening
<SERVER_NICKNAME> = an abbreviation or short name for the server
<SERVER_USERNAME> = admin username on the server, not root
<PUBLIC_SSH_KEY> = public SSH key that should be added to authorized_keys
```
