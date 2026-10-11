#!/usr/bin/env python3
"""Exercise real SSH/SCP against an isolated, loopback-only Docker SSH server."""

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]


def run(*arguments, check=True, **kwargs):
    result = subprocess.run(arguments, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=900, **kwargs)
    if check and result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {arguments[0]}\n{result.stdout[-12000:]}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', default='ubuntu:24.04')
    args = parser.parse_args()
    container = f'dotfiles-ssh-test-{uuid.uuid4().hex[:12]}'
    with tempfile.TemporaryDirectory(prefix='dotfiles-ssh-test-') as temporary:
        work = Path(temporary)
        try:
            run('docker', 'run', '-d', '--name', container, '-p', '127.0.0.1::22', args.image, 'sleep', 'infinity')
            run('docker', 'exec', '-i', container, 'bash', '-s', input='''set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends openssh-server ca-certificates curl git sudo fish
mkdir -p /run/sshd /root/.ssh
chmod 700 /root/.ssh
ssh-keygen -A
useradd --create-home --shell /bin/bash remote-test
passwd -d root
# Exercise the remote quoting through Fish, too.
usermod --shell /usr/bin/fish root
''')
            run('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(work / 'key'))
            run('docker', 'cp', str(work / 'key.pub'), f'{container}:/root/.ssh/authorized_keys')
            run('docker', 'exec', container, 'chown', 'root:root', '/root/.ssh/authorized_keys')
            run('docker', 'exec', container, 'chmod', '600', '/root/.ssh/authorized_keys')
            run('docker', 'exec', '-d', container, '/usr/sbin/sshd', '-D', '-E', '/tmp/sshd-test.log',
                '-o', 'PermitRootLogin=prohibit-password', '-o', 'PasswordAuthentication=no')
            port = run('docker', 'port', container, '22/tcp').stdout.strip().rsplit(':', 1)[1]
            host_key = run('docker', 'exec', container, 'cat', '/etc/ssh/ssh_host_ed25519_key.pub').stdout.split()
            # Pin the key obtained directly from the fixture, not from an unauthenticated network scan.
            trusted = f'[127.0.0.1]:{port} {host_key[0]} {host_key[1]}\n'
            known_hosts = work / 'known_hosts'
            known_hosts.write_text(trusted)
            config = work / 'config'
            config.write_text(f'''Host dotfiles-fixture
    HostName 127.0.0.1
    Port {port}
    User root
    IdentityFile "{work / 'key'}"
    IdentitiesOnly yes
    UserKnownHostsFile "{known_hosts}"
    StrictHostKeyChecking yes
''')
            (work / 'bin').mkdir()
            for tool in ['ssh', 'scp']:
                wrapper = work / 'bin' / tool
                wrapper.write_text(f'#!/bin/sh\nexec /usr/bin/{tool} -F {shlex.quote(str(config))} "$@"\n')
                wrapper.chmod(0o700)
            (work / 'home').mkdir()
            environment = {**os.environ, 'PATH': str(work / 'bin') + ':' + os.environ['PATH'],
                           'HOME': str(work / 'home')}
            base = ('bash', str(ROOT / 'install/install.sh'), '--remote=dotfiles-fixture',
                    '--yes', '--skip-ssh', '--skip-plugins', '--no-shell-change', '--groups=none')
            result = run(*base, '--admin-user=remote-test', env=environment, cwd=ROOT)
            assert 'Setup finished successfully.' in result.stdout, result.stdout[-5000:]
            expected = run('git', '-C', str(ROOT), 'rev-parse', 'HEAD').stdout.strip()
            actual = run('docker', 'exec', '-u', 'remote-test', container, 'git', '-C',
                         '/home/remote-test/.homesick/repos/dotfiles', 'rev-parse', 'HEAD').stdout.strip()
            assert actual == expected, (actual, expected)
            print('Real SSH/SCP installation from the committed snapshot passed (Fish login shell).', flush=True)

            failure = run(*base, '--admin-user=missing-account', env=environment, cwd=ROOT, check=False)
            assert failure.returncode != 0, failure.stdout[-5000:]
            assert 'Unattended setup requires an existing user' in failure.stdout, failure.stdout[-5000:]
            leftovers = run('docker', 'exec', container, 'find', '/tmp', '-maxdepth', '1', '-name', 'dotfiles-remote.*').stdout.strip()
            assert not leftovers, leftovers
            print('Remote failure propagation and temporary-directory cleanup passed.', flush=True)

            wrong_key = (work / 'key.pub').read_text().split()
            known_hosts.write_text(f'[127.0.0.1]:{port} {wrong_key[0]} {wrong_key[1]}\n')
            rejected = run(*base, '--admin-user=remote-test', env=environment, cwd=ROOT, check=False)
            assert rejected.returncode != 0
            assert 'HOST IDENTIFICATION HAS CHANGED' in rejected.stdout, rejected.stdout[-5000:]
            print('Changed host keys are rejected.', flush=True)
        except BaseException:
            print(run('docker', 'exec', container, 'cat', '/tmp/sshd-test.log', check=False).stdout, flush=True)
            raise
        finally:
            run('docker', 'rm', '-f', container, check=False)


if __name__ == '__main__':
    main()
