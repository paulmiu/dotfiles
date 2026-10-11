#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export PYTHONDONTWRITEBYTECODE=1
files=(install/install.sh install/lib/*.sh install/os/*.sh install/utils/*.sh install/os/resources/macos/scripts/defaults-import install/os/resources/macos/scripts/defaults-export install/os/resources/macos/scripts/symlink-gnubin-brew-packages install/tests/*.sh)
for file in "${files[@]}"; do bash -n "$file"; done
shellcheck "${files[@]}"
shfmt -d -i 4 -ci "${files[@]}"
python3 -m unittest discover -s install/tests -p 'test_*.py' -v
