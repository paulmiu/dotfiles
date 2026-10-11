#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=install/lib/linux.sh
source "$INSTALL_ROOT/lib/linux.sh"
linux_main debian "$@"
