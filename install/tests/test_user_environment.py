from pathlib import Path
import tempfile
import unittest

from test_installers import bash


class UserEnvironmentTests(unittest.TestCase):
    def test_account_setup_changes_to_target_home(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / 'target-home'
            (home / '.homesick/repos/dotfiles/.git').mkdir(parents=True)
            result = bash('source install/lib/user.sh; HOME=$1; '
                          'clone_dependency() { :; }; '
                          'backup_and_link_dotfiles() { [[ $PWD == "$HOME" ]] || die "wrong working directory"; }; '
                          'user_main main true ""', home)
            self.assertEqual(result.returncode, 0, result.stderr)
