"""Installer regression tests. Commands run only in temporary directories or as mocks."""

import os
from pathlib import Path
import subprocess
import tempfile
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


if __name__ == "__main__":
    unittest.main()
