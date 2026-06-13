# This guide is an example how to setup a fedora server after a clean installation

Tested with Fedora 22 and above.  
A description of the Variables used in this guide can be found at the bottom.

## On the server

### STEP 1: Login as root user

### STEP 2: Creating your admins user account and add it to the sudoers group

If you already created an user account for the admin, skip this step.
Otherwise create your admins user account:

```bash
adduser <SERVER_USERNAME>
passwd <SERVER_USERNAME>
gpasswd wheel -a <SERVER_USERNAME>
```

### STEP 3: Install the most important tools

```bash
dnf update
dnf install git vim tmux fish
```

### STEP 4: Clone the dotfiles from these reporitory

```bash
git clone https://github.com/andsens/homeshick.git $HOME/.homesick/repos/homeshick
$HOME/.homesick/repos/homeshick/bin/homeshick clone paulmiu/dotfiles
```

### STEP 5: Login to your admins user account

```bash
su - <SERVER_USERNAME>
```

### STEP 6: Configure git

```bash
git config --global user.name "<FIRST_NAME> <LAST_NAME>"
git config --global user.email "<EMAIL_ADDRESS>"
```

### STEP 7: Clone the dotfiles from these reporitory

```bash
git clone https://github.com/andsens/homeshick.git $HOME/.homesick/repos/homeshick
$HOME/.homesick/repos/homeshick/bin/homeshick clone paulmiu/dotfiles
```

## On the client

### STEP 1: Setup ssh config to login easily with `ssh <SERVER_NICKNAME>`

Insert following four lines in `$HOME/.ssh/config` on the host:

```bash
Host <SERVER_NICKNAME>
  User <SERVER_USERNAME>
  HostName <SERVER_HOSTNAME>
  Port <SERVER_PORT>
  SendEnv TMUX_AUTOSTART
```

### STEP 2: Add clients public key to your servers athorized keys

This step will enable you to ssh into your server without passphrase.

If you have the `ssh-copy-id` command on your client it's only:

```bash
ssh-copy-id <SERVER_NICKNAME>
```

Otherwise you have to call:

```bash
cat $HOME/.ssh/id_rsa.pub | ssh <SERVER_NICKNAME> "mkdir -p $HOME/.ssh; and cat >> .ssh/authorized_keys"
```

If you use _bash_ or _zsh_ on the client, replace the `; and` with `&&`.

## Extras

### To start tmux automatically after login add following line to `/etc/ssh/sshd_config`

```bash
AcceptEnv TMUX_AUTOSTART
```

After that you have to restart the ssh server with:

```bash
systemctl restart sshd.service
```

## Variables in this guide

```bash
<SERVER_HOSTNAME> = servers hostname or IP address
<SERVER_PORT> = port on server where the ssh service is listening
<SERVER_NICKNAME> = an abbreviation/short name for the server
<SERVER_USERNAME> = the admins username on the server (not root)
<FIRST_NAME> = admins first name
<LAST_NAME> = admins last name
<EMAIL_ADDRESS> = admins email address
```
