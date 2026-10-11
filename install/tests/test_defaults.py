import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'os/resources/macos/scripts/defaults_archive.py'
SPEC = importlib.util.spec_from_file_location('defaults_archive', SCRIPT)
defaults = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(defaults)


class DefaultsArchiveTests(unittest.TestCase):
    def archive(self, root, entries):
        path = Path(root) / 'preferences.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            for name, content in entries:
                archive.writestr(name, content)
        return path

    def test_rejects_unsafe_paths_symlinks_duplicates_and_invalid_plists(self):
        plist = plistlib.dumps({'value': True})
        symlink = zipfile.ZipInfo('user/com.example.plist')
        symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
        bad_cases = [
            [('../outside.plist', plist)], [('/user/test.plist', plist)],
            [(symlink, b'/etc/passwd')], [('user/com.example.plist', b'invalid')],
            [('user/com.example.plist', plist), ('apple/com.example.plist', plist)],
        ]
        for entries in bad_cases:
            with tempfile.TemporaryDirectory() as root:
                path = self.archive(root, entries)
                with patch.object(defaults, 'command') as command:
                    with self.assertRaises((ValueError, plistlib.InvalidFileException)):
                        defaults.import_archive(path)
                    command.assert_not_called()

    def test_size_limits_are_enforced_before_writes(self):
        with tempfile.TemporaryDirectory() as root:
            path = self.archive(root, [('user/com.example.plist', b'x' * 20)])
            with patch.object(defaults, 'MAX_PLIST', 10):
                with self.assertRaisesRegex(ValueError, 'size'):
                    defaults.read_archive(path)

    def test_export_does_not_overwrite_existing_backup(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'backup.zip'
            path.write_bytes(b'existing backup')
            with self.assertRaises(FileExistsError):
                defaults.export_archive(path)
            self.assertEqual(path.read_bytes(), b'existing backup')

    def test_failed_import_restores_previous_preferences(self):
        with tempfile.TemporaryDirectory() as root:
            old = plistlib.dumps({'value': 'original'})
            new = plistlib.dumps({'value': 'new'})
            path = self.archive(root, [('user/com.example.one.plist', new),
                                       ('user/com.example.two.plist', new)])
            restored = []

            def command(is_root, operation, *args):
                self.assertFalse(is_root)
                if operation == 'domains':
                    return b'com.example.one, com.example.two'
                if operation == 'export':
                    return old
                if operation == 'import':
                    content = Path(args[1]).read_bytes()
                    if args[0] == 'com.example.two' and content == new:
                        raise subprocess.CalledProcessError(1, 'defaults')
                    if content == old:
                        restored.append(args[0])
                    return b''
                raise AssertionError(operation)

            with patch.object(defaults, 'command', side_effect=command), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(subprocess.CalledProcessError):
                    defaults.import_archive(path, backup_parent=Path(root) / 'backups')
            self.assertEqual(restored, ['com.example.two', 'com.example.one'])

    def test_root_preferences_require_explicit_selection(self):
        with tempfile.TemporaryDirectory() as root:
            path = self.archive(root, [('global/com.example.plist', plistlib.dumps({}))])
            with patch.object(defaults, 'command') as command:
                with self.assertRaisesRegex(ValueError, 'no selected'):
                    defaults.import_archive(path)
                command.assert_not_called()
