#!/usr/bin/env bash
# Standalone HTTPS bootstrap and checkout entry point. Bash 3.2 compatible.
set -Eeuo pipefail

bootstrap() (
    umask 077
    local work ref=main argument previous='' sha
    for argument in "$@"; do
        if [[ $previous == --ref ]]; then ref=$argument; fi
        case $argument in --ref=*) ref=${argument#*=} ;; esac
        previous=$argument
    done
    [[ $ref =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ && $ref != *..* ]] || {
        printf 'Invalid Git ref.\n' >&2
        exit 1
    }
    work=$(mktemp -d /tmp/dotfiles-bootstrap.XXXXXXXX)
    trap 'rm -rf "$work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    fetch() {
        if command -v curl >/dev/null 2>&1; then
            curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 300 --retry 2 "$1" -o "$2"
        elif command -v wget >/dev/null 2>&1; then
            wget --https-only --timeout=30 --tries=3 -qO "$2" "$1"
        else
            printf 'Install curl or wget first.\n' >&2
            return 1
        fi
    }
    # Resolve once so every file in this installation comes from the same revision.
    fetch "https://api.github.com/repos/mamiu/dotfiles/commits/$ref" "$work/commit.json"
    sha=$(sed -n '/^[[:space:]]*"sha": /{s/.*"sha": "\([0-9a-f]*\)".*/\1/;p;q;}' "$work/commit.json")
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || {
        printf 'Could not resolve the requested revision.\n' >&2
        exit 1
    }
    fetch "https://codeload.github.com/mamiu/dotfiles/tar.gz/$sha" "$work/source.tar.gz"
    tar -tzf "$work/source.tar.gz" >"$work/manifest"
    if grep -Eq '(^/|(^|/)\.\.(/|$))' "$work/manifest"; then
        printf 'Unsafe archive path.\n' >&2
        exit 1
    fi
    mkdir "$work/source"
    tar -xzf "$work/source.tar.gz" --strip-components=1 -C "$work/source"
    [[ -f $work/source/install/lib/launcher.sh ]] || {
        printf 'This revision predates the modular installer; use a published ref containing it.\n' >&2
        exit 1
    }
    bash "$work/source/install/install.sh" "$@" "--ref=$sha"
)

main() {
    local install_root=''
    if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
        install_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    fi
    if [[ -n $install_root && -f $install_root/lib/launcher.sh ]]; then
        INSTALL_ROOT=$install_root
        # shellcheck source=install/lib/launcher.sh
        source "$install_root/lib/launcher.sh"
        launcher_main "$@"
    else
        if [[ ${1:-} == --help || ${1:-} == -h ]]; then
            printf 'Usage: install.sh [--local | --remote USER@HOST] [--port PORT] [--ref REF] [installer options]\nDownload a complete checkout to inspect the detailed --help or run --dry-run offline.\n'
            return 0
        fi
        bootstrap "$@"
    fi
}
main "$@"
