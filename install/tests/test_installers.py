"""Installer regression tests. Commands run only in temporary directories or as mocks."""

import os
from pathlib import Path
import subprocess
import tempfile
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHELL = os.environ.get("TEST_BASH", "/bin/bash")


def bash(code, *args, env=None):
    return subprocess.run(
        [SHELL, "-c", code, "test", *map(str, args)],
        cwd=ROOT, text=True, capture_output=True,
        env={**os.environ, **(env or {})}, timeout=30,
    )


class CommonTests(unittest.TestCase):
    def common(self, code, *args):
        return bash('source install/lib/common.sh; installer_init; ' + code, *args)

    def test_port_bounds_and_shell_input(self):
        for port in ["1", "22", "00022", "65535"]:
            self.assertEqual(self.common('valid_port "$1"', port).returncode, 0)
        for port in ["0", "65536", "-1", "1+2", "22;touch x", "999999999", ""]:
            self.assertNotEqual(self.common('valid_port "$1"', port).returncode, 0)

    def test_missing_option_values_and_unknown_options(self):
        for args in [("--admin-user",), ("--admin-user=",), ("--groups", "--yes"),
                     ("--yes=no",), ("--wat",), ("--skip-ssh", "--new-ssh-port=22")]:
            self.assertNotEqual(self.common('parse_options "$@"', *args).returncode, 0)

    def test_option_values_are_not_executed(self):
        result = self.common('parse_options "$@"; printf "%s" "$PUBLIC_SSH_KEY"',
                             "--add-ssh-key=$(exit 42)")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "$(exit 42)")

    def test_groups_validate_deduplicate_and_allow_none(self):
        setup = ('parse_options "$@"; GROUP_IDS=(core tools); GROUP_LABELS=(Core Tools); '
                 'GROUP_DEFAULTS=(yes no); select_groups; printf "%s" "${SELECTED_GROUPS[*]:-}"')
        for argument, expected in [("--groups=core,core,tools", "core tools"),
                                   ("--groups=none", ""), ("--yes", "core")]:
            result = self.common(setup, argument)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected)
        self.assertNotEqual(self.common(setup, "--groups=unknown").returncode, 0)

    def test_failure_stops_execution_and_preserves_status(self):
        result = self.common('(exit 23); printf should-not-run')
        self.assertEqual(result.returncode, 23)
        self.assertNotIn("should-not-run", result.stdout)

    def test_failed_download_does_not_replace_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "download"
            target.write_text("original")
            result = self.common('curl() { printf partial > "${!#}"; return 22; }; '
                                 'download_file https://example.invalid/file "$1"', target)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), "original")
            self.assertEqual(list(Path(directory).iterdir()), [target])

    def test_rejects_plain_http(self):
        result = self.common('download_file http://example.invalid/file /unused')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTTPS", result.stderr)


class LinuxTests(unittest.TestCase):
    def test_platform_help_and_dry_run_work_without_root(self):
        for platform in ["ubuntu", "debian", "fedora"]:
            for option in ["--help", "--dry-run"]:
                result = bash('bash "$1" "$2"', f'install/os/{platform}.sh', option)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_prerequisites_are_installed_when_no_groups_selected(self):
        result = bash('source install/lib/linux.sh; installer_init; parse_options --groups=none; '
                      'DISTRO=ubuntu; linux_groups; select_groups; linux_packages; printf "%s\\n" "${PACKAGES[@]}"')
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ["sudo", "ca-certificates", "openssh-server", "git"]:
            self.assertIn(name, result.stdout.splitlines())
        self.assertNotIn("fish", result.stdout.splitlines())

    def test_failed_package_install_stops_before_account_changes(self):
        result = bash('source install/lib/linux.sh; require_root() { :; }; linux_preflight() { :; }; '
                      'mkdir() { :; }; rmdir() { :; }; '
                      'apt-get() { return 42; }; prepare_linux_user() { echo unsafe; }; '
                      'linux_main ubuntu --yes --skip-ssh --skip-plugins --groups=none')
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertNotIn("unsafe", result.stdout)
        self.assertNotIn("completed successfully", result.stdout)

    def test_upgrade_is_opt_in(self):
        result = bash('source install/lib/linux.sh; installer_init; parse_options --yes; '
                      'DISTRO=ubuntu; PACKAGES=(sudo); apt-get() { printf "%s\\n" "$*"; }; install_linux_packages')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("upgrade", result.stdout)
        self.assertNotIn("--allow-", result.stdout)


class LauncherTests(unittest.TestCase):
    def test_remote_argument_quoting_round_trips_without_execution(self):
        for value in ["space separated", "a'b", "$(exit 42)", "line1\nline2", "`exit 42`", ""]:
            result = bash('source install/lib/launcher.sh; shell_quote "$1"', value)
            self.assertEqual(result.returncode, 0, result.stderr)
            executed = subprocess.run(["/bin/sh", "-c", "printf '%s' " + result.stdout],
                                      text=True, capture_output=True, timeout=5)
            self.assertEqual(executed.returncode, 0)
            self.assertEqual(executed.stdout, value)

    def test_invalid_remote_targets_and_conflicting_modes(self):
        for args in [("--remote=-oProxyCommand=bad",), ("--remote=a;exit",),
                     ("--remote=a@b@c",), ("--local", "--remote=host"), ("--local", "--port=22")]:
            result = bash('source install/lib/launcher.sh; installer_init; parse_launcher_options "$@"', *args)
            self.assertNotEqual(result.returncode, 0)

    def test_remote_dry_run_does_not_connect(self):
        result = bash('source install/lib/launcher.sh; ssh() { echo unexpected-ssh; return 42; }; '
                      'launcher_main --remote=root@example.com --dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("unexpected-ssh", result.stdout)

    def test_local_failure_is_not_hidden_by_logging(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "os").mkdir()
            (root / "os/ubuntu.sh").write_text('exit 37\n')
            result = bash('source install/lib/launcher.sh; installer_init; INSTALL_ROOT=$1; HOME=$1; '
                          'sudo() { shift; "$@"; }; detect_platform() { echo ubuntu; }; '
                          'parse_launcher_options --local --yes; local_install', root)
            self.assertEqual(result.returncode, 37, result.stderr)
            self.assertNotIn("finished successfully", result.stdout)

    def test_payload_contains_committed_snapshot_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            repo.mkdir()
            (repo / "install/lib").mkdir(parents=True)
            (repo / "install/lib/launcher.sh").write_text('# fixture\n')
            (repo / "tracked").write_text('committed')
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Installer Test',
                            '-c', 'user.email=installer@example.invalid', '-c', 'commit.gpgsign=false',
                            'commit', '-qm', 'fixture'], check=True)
            (repo / "tracked").write_text('uncommitted')
            (repo / "staged").write_text('private unrelated change')
            subprocess.run(['git', '-C', str(repo), 'add', 'staged'], check=True)
            result = bash('source install/lib/launcher.sh; installer_init; DOTFILES_REF=main; '
                          'prepare_payload "$1" "$2"', repo, root / "payload")
            self.assertEqual(result.returncode, 0, result.stderr)
            with tarfile.open(root / "payload/payload.tar.gz") as archive:
                self.assertEqual(archive.extractfile('./tracked').read(), b'committed')
                self.assertNotIn('./staged', archive.getnames())
                self.assertIn('./install/source.bundle', archive.getnames())


class MacOSTests(unittest.TestCase):
    def test_dry_run_has_no_privileged_actions(self):
        result = bash('source install/lib/macos.sh; sudo() { echo unexpected-sudo; return 44; }; '
                      'macos_main --dry-run --groups=essentials')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("unexpected-sudo", result.stdout)
        self.assertIn("fish", result.stdout)

    def test_linux_only_options_are_rejected(self):
        for option in ["--new-ssh-port=22222", "--hostname=test", "--reboot", "--upgrade"]:
            result = bash('bash install/os/macos.sh --dry-run "$1"', option)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Linux-only", result.stderr)

    def test_preferences_are_opt_in(self):
        result = bash('source install/lib/macos.sh; installer_init; parse_options --yes; '
                      'macos_groups; select_groups; group_selected preferences')
        self.assertNotEqual(result.returncode, 0)


class SelectionTests(unittest.TestCase):
    def test_legacy_helper_rejects_variable_name_injection(self):
        result = bash('source install/utils/multiselect.sh; multiselect true "$1" options', 'result[$(exit 42)]')
        self.assertNotEqual(result.returncode, 0)

    def test_selection_toggles_without_eval_or_terminal_control(self):
        if bash('(( BASH_VERSINFO[0] >= 4 ))').returncode:
            self.skipTest('Nameref compatibility helper requires Bash 4.3+')
        result = bash('source install/utils/multiselect.sh; options=(one two); defaults=(true false); '
                      'multiselect false result options defaults <<< $\'1 2\\n\\n\'; '
                      'printf "RESULT:%s" "${result[*]}"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('RESULT:false true', result.stdout)


class UserFilesTests(unittest.TestCase):
    def test_conflicting_dotfiles_are_backed_up_and_reruns_preserve_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "home"
            castle = Path(directory) / "castle"
            home.mkdir()
            (castle / "home").mkdir(parents=True)
            (home / ".vimrc").write_text("personal config")
            (castle / "home/.vimrc").write_text("managed config")
            code = ('source install/lib/user.sh; installer_init; HOME=$1; USER_WORK=$1; '
                    'backup_and_link_dotfiles "$2"; backup_and_link_dotfiles "$2"')
            result = bash(code, home, castle)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((home / ".vimrc").is_symlink())
            backups = list(home.glob(".local/state/dotfiles/backups/*/.vimrc"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), "personal config")

    def test_symlinked_parent_is_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "home").mkdir()
            (root / "outside").mkdir()
            (root / "castle/home/.config").mkdir(parents=True)
            (root / "castle/home/.config/test").write_text("managed")
            (root / "home/.config").symlink_to(root / "outside")
            result = bash('source install/lib/user.sh; installer_init; HOME=$1; USER_WORK=$1; '
                          'backup_and_link_dotfiles "$2"', root / "home", root / "castle")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list((root / "outside").iterdir()), [])

    def test_authorized_key_is_deduplicated_and_private(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".ssh").mkdir()
            authorized = home / ".ssh/authorized_keys"
            authorized.write_text('restrict ssh-ed25519 AAAA existing comment')
            result = bash('source install/lib/user.sh; installer_init; HOME=$1; '
                          'authorize_key "ssh-ed25519 AAAA new comment"; '
                          'authorize_key "ssh-ed25519 BBBB another key"; '
                          'authorize_key "ssh-ed25519 BBBB repeated"', home)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(authorized.read_text().count("AAAA"), 1)
            self.assertEqual(authorized.read_text().count("BBBB"), 1)
            self.assertEqual(authorized.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
