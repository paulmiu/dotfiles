#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=install/lib/macos.sh
source "$INSTALL_ROOT/lib/macos.sh"
macos_main "$@"
