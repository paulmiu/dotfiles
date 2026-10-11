#!/usr/bin/env bash
# Shared Linux provisioning; the platform entry point selects its package manager.
# shellcheck source=install/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=install/lib/ssh.sh
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh"

linux_groups() {
    GROUP_IDS=(basic essentials remote terminal search kubernetes)
    GROUP_LABELS=('basic system tools' 'Fish, Vim, tmux and Git' 'Mosh' 'ncdu and htop' 'fzf, bat, fd, ripgrep and jq' 'kubectx and kubens')
    GROUP_DEFAULTS=(yes yes yes yes yes no)
    if [[ $DISTRO == fedora ]]; then
        GROUP_IDS+=(cockpit)
        GROUP_LABELS+=('Cockpit web console (opens its firewall service)')
        GROUP_DEFAULTS+=(no)
    fi
}

linux_packages() {
    # Prerequisites are mandatory even when all optional groups are deselected.
    PACKAGES=(ca-certificates curl git sudo openssh-server)
    if [[ $DISTRO == fedora ]]; then
        PACKAGES+=(openssh-clients shadow-utils util-linux-user)
    else
        PACKAGES+=(adduser passwd util-linux)
    fi
    if group_selected basic; then
        PACKAGES+=(net-tools gawk)
        if [[ $DISTRO == fedora ]]; then PACKAGES+=(tar lsof bind-utils); else PACKAGES+=(uidmap); fi
    fi
    if group_selected essentials; then PACKAGES+=(vim fish tmux); fi
    if group_selected remote; then PACKAGES+=(mosh); fi
    if group_selected terminal; then PACKAGES+=(ncdu htop); fi
    if group_selected search; then PACKAGES+=(fzf bat fd-find ripgrep jq); fi
    if group_selected kubernetes; then PACKAGES+=(kubectx); fi
    if group_selected cockpit; then PACKAGES+=(cockpit); fi
    if [[ $DISTRO == fedora && -n $NEW_SSH_PORT ]]; then PACKAGES+=(policycoreutils-python-utils); fi
}

systemd_available() {
    [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

linux_service_preflight() {
    if systemd_available; then return 0; fi
    # Optional SSH integration must not block dotfiles in a managed shell or container.
    # Explicit requests still fail before any packages, accounts or configuration change.
    [[ -z $NEW_SSH_PORT ]] || die '--new-ssh-port requires a running systemd.'
    [[ -z $NEW_HOSTNAME ]] || die '--hostname requires a running systemd.'
    [[ $REBOOT != true ]] || die '--reboot requires a running systemd.'
    if group_selected cockpit; then die 'Cockpit setup requires a running systemd.'; fi
    if [[ $SKIP_SSH != true ]]; then
        warn 'No running systemd found; skipping SSH daemon configuration.'
        SKIP_SSH=true
    fi
}

linux_preflight() {
    local actual_id version
    [[ -r /etc/os-release ]] || die 'Cannot identify the Linux distribution.'
    actual_id=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '\042\047')
    [[ $actual_id == "$DISTRO" ]] || die "This entry point is for $DISTRO, but the system is $actual_id."
    if [[ $DISTRO == debian ]]; then
        version=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '\042\047')
        [[ $version =~ ^[0-9]+(\.[0-9]+)*$ ]] || die 'Cannot determine the Debian version.'
        ((${version%%.*} >= 13)) || die 'The Debian installer targets Debian 13 (Trixie) or newer.'
    fi
    if [[ $DISTRO == fedora ]]; then require_command dnf; else require_command apt-get; fi
    linux_service_preflight
    ADMIN_USER=${ADMIN_USER:-${SUDO_USER:-root}}
    valid_user "$ADMIN_USER" || die 'Invalid target username.'
    if ! id "$ADMIN_USER" >/dev/null 2>&1 && [[ $ASSUME_YES == true ]]; then
        die 'Unattended setup requires an existing user. Create the admin interactively so a sudo password can be set.'
    fi
}

install_linux_packages() {
    log "Installing packages: ${PACKAGES[*]}"
    if [[ $DISTRO == fedora ]]; then
        if [[ $UPGRADE == true ]]; then dnf -y upgrade; fi
        dnf -y install "${PACKAGES[@]}"
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        if [[ $UPGRADE == true ]]; then
            apt-get -o Dpkg::Options::=--force-confold -y upgrade
        fi
        apt-get -o Dpkg::Options::=--force-confold -y --no-install-recommends install "${PACKAGES[@]}"
    fi
}

prepare_linux_user() {
    local admin_group=sudo current_shell
    if [[ $DISTRO == fedora ]]; then admin_group=wheel; fi
    if ! id "$ADMIN_USER" >/dev/null 2>&1; then
        useradd --create-home --shell /bin/bash "$ADMIN_USER"
        log "Set the password used by $ADMIN_USER for sudo."
        passwd "$ADMIN_USER" </dev/tty
    fi
    if [[ $ADMIN_USER != root ]]; then usermod -a -G "$admin_group" "$ADMIN_USER"; fi
    TARGET_HOME=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
    [[ -d $TARGET_HOME && $TARGET_HOME == /* && $TARGET_HOME != / ]] || die "Invalid home directory for $ADMIN_USER"
    [[ $(stat -c %u "$TARGET_HOME") == "$(id -u "$ADMIN_USER")" ]] || die 'Target user does not own their home directory.'
    if [[ $CHANGE_SHELL == true ]] && group_selected essentials; then
        local fish_path
        fish_path=$(command -v fish)
        if ! grep -Fqx "$fish_path" /etc/shells; then printf '%s\n' "$fish_path" >>/etc/shells; fi
        current_shell=$(getent passwd "$ADMIN_USER" | cut -d: -f7)
        if [[ $current_shell != "$fish_path" ]]; then usermod --shell "$fish_path" "$ADMIN_USER"; fi
    fi
}

run_user_setup() (
    local stage repo bundle=''
    stage=$(mktemp -d /tmp/dotfiles-user.XXXXXX)
    trap 'rm -rf "$stage"' EXIT
    repo=$(cd "$INSTALL_ROOT/.." && pwd)
    cp "$INSTALL_ROOT/lib/common.sh" "$INSTALL_ROOT/lib/user.sh" "$stage/"
    # A local checkout is installed from its committed snapshot, including unpublished commits.
    # Staged and unstaged work is never copied to another account or host.
    if [[ -f $INSTALL_ROOT/source.bundle && $DOTFILES_REF == main ]]; then
        cp "$INSTALL_ROOT/source.bundle" "$stage/dotfiles.bundle"
        bundle="$stage/dotfiles.bundle"
    elif [[ -e $repo/.git && $DOTFILES_REF == main ]]; then
        git -c safe.directory="$repo" -C "$repo" bundle create "$stage/dotfiles.bundle" HEAD
        bundle="$stage/dotfiles.bundle"
    fi
    chown -R "$ADMIN_USER:$(id -gn "$ADMIN_USER")" "$stage"
    sudo -H -u "$ADMIN_USER" env -i HOME="$TARGET_HOME" USER="$ADMIN_USER" LOGNAME="$ADMIN_USER" \
        PATH="$PATH" TERM="${TERM:-dumb}" LANG="${LANG:-C.UTF-8}" \
        /bin/bash "$stage/user.sh" "$DOTFILES_REF" "$SKIP_PLUGINS" "$PUBLIC_SSH_KEY" "$bundle"
)

linux_main() {
    installer_init
    DISTRO=$1
    shift
    parse_options "$@"
    if [[ $SHOW_HELP == true ]]; then
        installer_usage
        linux_groups
        log "Groups: ${GROUP_IDS[*]}"
        return 0
    fi
    linux_groups
    select_groups
    linux_packages
    if [[ $DRY_RUN != true ]]; then
        require_root
        linux_preflight
    fi
    print_plan "$DISTRO"
    log "Packages: ${PACKAGES[*]}"
    if [[ $DRY_RUN == true ]]; then return 0; fi
    if [[ -n $PUBLIC_SSH_KEY ]]; then validate_public_key "$PUBLIC_SSH_KEY"; fi
    confirm 'Apply this installation plan?' yes || die 'Installation cancelled.'
    mkdir /run/dotfiles-installer.lock 2>/dev/null || die 'Another installer is running, or /run/dotfiles-installer.lock remains from an interrupted run.'
    trap 'rmdir /run/dotfiles-installer.lock' EXIT
    install_linux_packages
    prepare_linux_user
    run_user_setup
    if [[ -n $NEW_HOSTNAME ]]; then hostnamectl set-hostname "$NEW_HOSTNAME"; fi
    if [[ $SKIP_SSH != true ]]; then configure_ssh; fi
    if group_selected cockpit; then
        systemctl enable --now cockpit.socket
        if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
            firewall-cmd --add-service=cockpit
            firewall-cmd --permanent --add-service=cockpit
        fi
    fi
    if [[ $REBOOT == true ]]; then shutdown -r +1 'Dotfiles installation complete'; fi
    log 'Installation completed successfully.'
}
