#!/usr/bin/env bash
# Run inside the disposable Linux test container: validates with the real OpenSSH parser.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source install/lib/common.sh
source install/lib/ssh.sh
installer_init
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p /run/sshd
ssh-keygen -q -t ed25519 -N '' -f "$work/key"
SSHD=/usr/sbin/sshd DISTRO=ubuntu NEW_SSH_PORT=22222
export SSHD
printf 'HostKey %s\nUsePAM no\nMatch User nobody\n    X11Forwarding no\n' "$work/key" >"$work/sshd_config"
systemctl() {
    if [[ $1 == is-active && $3 == *.socket ]]; then return 1; fi
    if [[ ${FAIL_ACTIVATION:-false} == true && $1 == reload-or-restart ]]; then return 41; fi
    return 0
}
configure_ssh "$work/sshd_config" "$work/units"
ssh_ports "$work/sshd_config" >"$work/ports"
grep -qx 22 "$work/ports"
grep -qx 22222 "$work/ports"
cp "$work/sshd_config" "$work/first"
configure_ssh "$work/sshd_config" "$work/units"
cmp "$work/first" "$work/sshd_config"

# Do not wrap configure_ssh in `if`: Bash disables errexit inside conditional functions.
set +e
trap - ERR
(
    installer_init
    FAIL_ACTIVATION=true
    NEW_SSH_PORT=22223
    configure_ssh "$work/sshd_config" "$work/units"
)
status=$?
installer_init
[[ $status == 41 ]]
cmp "$work/first" "$work/sshd_config"

# Included provider ports must also survive a new managed port and Match blocks.
printf 'Port 2200\n' >"$work/provider.conf"
printf 'Include %s\nHostKey %s\n' "$work/provider.conf" "$work/key" >"$work/sshd_config"
configure_ssh "$work/sshd_config" "$work/units"
ssh_ports "$work/sshd_config" >"$work/ports"
grep -qx 2200 "$work/ports"
grep -qx 22222 "$work/ports"
printf 'OpenSSH validation, idempotency, included ports, and rollback passed.\n'
