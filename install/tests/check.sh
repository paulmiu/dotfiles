#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export PYTHONDONTWRITEBYTECODE=1
files=(install/lib/*.sh install/os/ubuntu.sh install/os/fedora.sh install/tests/*.sh)
for file in "${files[@]}"; do bash -n "$file"; done
shellcheck "${files[@]}"
shfmt -d -i 4 -ci "${files[@]}"
python3 -m unittest discover -s install/tests -p 'test_*.py' -v
