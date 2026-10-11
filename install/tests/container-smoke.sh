#!/usr/bin/env bash
# This test intentionally provisions its container. Invoke only inside a disposable container.
set -Eeuo pipefail
[[ -f /.dockerenv ]] || {
    printf 'Run this test in a disposable Docker container.\n' >&2
    exit 1
}
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
platform=${1:?Pass ubuntu, debian or fedora}
case $platform in ubuntu | debian | fedora) ;; *) exit 1 ;; esac
if [[ $platform == fedora ]]; then dnf -y install shadow-utils; fi
useradd --create-home --shell /bin/bash installer-test
printf 'personal configuration\n' >/home/installer-test/.vimrc
chown installer-test:installer-test /home/installer-test/.vimrc
# A regular install must work without systemd or an explicit --skip-ssh workaround.
args=(--yes --admin-user=installer-test --skip-plugins)
bash "install/os/$platform.sh" "${args[@]}"
test -L /home/installer-test/.vimrc
test -d /home/installer-test/.homesick/repos/dotfiles/.git
test "$(stat -c %U /home/installer-test/.homesick/repos/dotfiles)" = installer-test
backup=$(find /home/installer-test/.local/state/dotfiles/backups -name .vimrc -print -quit)
[[ -n $backup ]]
grep -qx 'personal configuration' "$backup"
if [[ $platform == fedora ]]; then admin_group=wheel; else admin_group=sudo; fi
id -nG installer-test | tr ' ' '\n' | grep -qx "$admin_group"
test "$(getent passwd installer-test | cut -d: -f7)" = /usr/bin/fish
before=$(git -c safe.directory=/home/installer-test/.homesick/repos/dotfiles -C /home/installer-test/.homesick/repos/dotfiles rev-parse HEAD)
cp /etc/ssh/sshd_config /tmp/sshd-before-rerun
printf 'local change\n' >/home/installer-test/.homesick/repos/dotfiles/local-change
bash "install/os/$platform.sh" "${args[@]}"
cmp /tmp/sshd-before-rerun /etc/ssh/sshd_config
after=$(git -c safe.directory=/home/installer-test/.homesick/repos/dotfiles -C /home/installer-test/.homesick/repos/dotfiles rev-parse HEAD)
[[ $before == "$after" ]]
grep -qx 'local change' /home/installer-test/.homesick/repos/dotfiles/local-change
bash install/tests/ssh-integration.sh
printf '%s container smoke test passed.\n' "$platform"
